defmodule Vaos.Ledger.Epistemic.Controller do
  @moduledoc """
  Chooses next research move from current ledger state.
  Port of AIEQ-Core ResearchController.
  """

  alias Vaos.Ledger.Epistemic.{Policy, Ledger, Models}

  @type option :: {:backlog_limit, pos_integer()} | {:mode_hint, String.t()}

  @doc """
  Decide on the next research action.
  """
  @spec decide(GenServer.server(), list(option())) :: Vaos.Ledger.Epistemic.Models.ControllerDecision.t()
  def decide(ledger, opts \\ []) do
    backlog_limit = Keyword.get(opts, :backlog_limit, 5)
    mode_hint = Keyword.get(opts, :mode_hint, "")

    # Get all non-archived claims
    all_claims = Ledger.list_claims()
    claims = Enum.reject(all_claims, &(&1.status == :archived))

    if Enum.empty?(claims) do
      primary = bootstrap_proposal(ledger, mode_hint)

      Models.ControllerDecision.new(
        queue_state: "bootstrap",
        summary: "No claims exist yet, so controller should bootstrap graph.",
        primary_action: primary,
        backlog: []
      )
    else
      # Build proposals for each claim using policy
      proposals = Policy.rank_actions(ledger, limit: backlog_limit * 2)

      if Enum.empty?(proposals) do
        # No automated proposals available
        primary = analysis_proposal(hd(claims))

        Models.ControllerDecision.new(
          queue_state: "analysis",
          summary: "No automated proposal is currently available for active claims.",
          primary_action: primary,
          backlog: []
        )
      else
        # Apply history feedback and rank
        proposals = Enum.map(proposals, &apply_history_feedback(ledger, &1))
        ranked = Enum.sort_by(proposals, & &1.expected_information_gain, :desc)

        primary = hd(ranked)
        backlog = Enum.slice(ranked, 1, backlog_limit)
        summary = build_summary(all_claims, primary)

        Models.ControllerDecision.new(
          queue_state: primary.stage || "exploration",
          summary: summary,
          primary_action: primary,
          backlog: backlog
        )
      end
    end
  end

  defp bootstrap_proposal(_ledger, mode_hint) do
    Models.ActionProposal.new(
      claim_id: "",
      claim_title: "ledger bootstrap",
      action_type: :propose_hypothesis,
      expected_information_gain: 1.0,
      priority: "now",
      reason: "The ledger is empty and needs its first target or claim.",
      executor: :manual,
      mode: mode_hint || "ml_research",
      stage: "bootstrap",
      command_hint: "Register a target or import a project before asking controller to run."
    )
  end

  defp analysis_proposal(claim) do
    Models.ActionProposal.new(
      claim_id: claim.id,
      claim_title: claim.title,
      action_type: :analyze_failure,
      expected_information_gain: 0.5,
      priority: "next",
      reason: "No automated proposal is currently available for active claims.",
      executor: :manual,
      mode: "ml_research",
      stage: "analysis",
      command_hint: "Inspect active claim and register missing target, eval, or project context."
    )
  end

  defp apply_history_feedback(_ledger, proposal) do
    if proposal.claim_id == "" do
      proposal
    else
      decisions =
        Ledger.decisions_for_claim(proposal.claim_id)
        |> Enum.filter(&(&1.action_type == proposal.action_type))

      executions =
        Ledger.executions_for_claim(proposal.claim_id)
        |> Enum.filter(&(&1.action_type == proposal.action_type))

      executed_decision_ids =
        executions
        |> Enum.filter(&(&1.decision_id != ""))
        |> Enum.map(& &1.decision_id)
        |> MapSet.new()

      pending_decisions = Enum.reject(decisions, &MapSet.member?(executed_decision_ids, &1.id))
      running = Enum.filter(executions, &(&1.status == :running))
      failed = Enum.filter(executions, &(&1.status == :failed))
      succeeded = Enum.filter(executions, &(&1.status == :succeeded))

      proposal
      |> apply_pending_or_running(pending_decisions, running)
      |> apply_failed_feedback(failed)
      |> apply_succeeded_feedback(succeeded)
    end
  end

  defp apply_pending_or_running(proposal, pending, running) do
    if not Enum.empty?(pending) or not Enum.empty?(running) do
      %{proposal |
        expected_information_gain: Models.clamp(proposal.expected_information_gain * 0.75),
        reason: proposal.reason <> " A similar action is already queued or in flight."
      }
    else
      proposal
    end
  end

  defp apply_failed_feedback(proposal, []) do
    proposal
  end

  defp apply_failed_feedback(proposal, failed) do
    failed_runtime = Enum.sum(Enum.map(failed, &(&1.runtime_seconds || 0.0)))
    failed_cost = Enum.sum(Enum.map(failed, &(&1.cost_estimate_usd || 0.0)))

    avg_failed_artifact_quality =
      if length(failed) > 0 do
        failed
        |> Enum.filter(&(not is_nil(&1.artifact_quality)))
        |> Enum.map(& &1.artifact_quality)
        |> then(fn
          [] -> 0.0
          scores -> Enum.sum(scores) / length(scores)
        end)
      else
        0.0
      end

    runtime_pressure = Models.clamp(failed_runtime / 1800.0)
    cost_pressure = Models.clamp(failed_cost / 5.0)
    artifact_pressure = Models.clamp(1.0 - avg_failed_artifact_quality)

    penalty =
      :math.pow(0.75, min(length(failed), 3)) *
        (1.0 - 0.20 * runtime_pressure) *
        (1.0 - 0.20 * cost_pressure) *
        (1.0 - 0.10 * artifact_pressure)

    reason_suffix =
      if runtime_pressure > 0.0 or cost_pressure > 0.0 do
        " Failed runs have already burned about #{:erlang.float_to_binary(failed_runtime, decimals: 1)}s " <>
          "and $#{:erlang.float_to_binary(failed_cost, decimals: 2)} on this action."
      else
        ""
      end

    %{proposal |
      expected_information_gain: Models.clamp(proposal.expected_information_gain * penalty),
      reason:
        proposal.reason <>
          " This action has failed #{length(failed)} time(s) already, so controller is " <>
            "discounting repeat attempts." <> reason_suffix
    }
  end

  defp apply_succeeded_feedback(proposal, []) do
    proposal
  end

  defp apply_succeeded_feedback(proposal, succeeded) do
    avg_success_artifact_quality =
      if length(succeeded) > 0 do
        succeeded
        |> Enum.filter(&(not is_nil(&1.artifact_quality)))
        |> Enum.map(& &1.artifact_quality)
        |> then(fn
          [] -> 0.0
          scores -> Enum.sum(scores) / length(scores)
        end)
      else
        0.0
      end

    if one_shot_action?(proposal.action_type) do
      %{proposal |
        expected_information_gain: Models.clamp(proposal.expected_information_gain * 0.35),
        reason: proposal.reason <> " This is a one-shot stage and has already succeeded once."
      }
    else
      quality_pressure = Models.clamp(1.0 - avg_success_artifact_quality)

      new_gain =
        Models.clamp(
          proposal.expected_information_gain * (0.92 - 0.10 * (1.0 - quality_pressure))
        )

      reason_suffix =
        if proposal.action_type == :triage_attack do
          " Similar critique work already completed recently."
        else
          " The controller is slightly discounting a repeated successful action."
        end

      %{proposal |
        expected_information_gain: new_gain,
        reason: proposal.reason <> reason_suffix
      }
    end
  end

  defp one_shot_action?(action_type) do
    Models.action_matches?(
      action_type,
      [
        :generate_idea,
        :generate_method,
        :synthesize_paper,
        :propose_hypothesis,
        :design_mutation,
        :synthesize_report,
        :promote_winner
      ]
    )
  end

  defp build_summary(all_claims, primary) do
    claim_count = Enum.count(all_claims, &(&1.status != :archived))

    cond do
      Models.action_matches?(primary.action_type, [:synthesize_paper, :synthesize_report]) ->
        "#{claim_count} active claims tracked. The top claim is stable enough that " <>
          "paper synthesis/reporting is now best move."

      Models.action_matches?(primary.action_type, [:generate_method, :design_mutation]) ->
        "#{claim_count} active claims tracked. The top claim is blocked on next " <>
          "mutation/design step."

      true ->
        "#{claim_count} active claims tracked. The highest-value next move is " <>
          "`#{primary.action_type}` on `#{primary.claim_title}`."
    end
  end
end
