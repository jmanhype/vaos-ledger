defmodule Vaos.Ledger.Epistemic.Policy do
  @moduledoc """
  Expected Information Gain Policy for ranking actions.
  Ranks next actions by how much they could change ledger's beliefs.

  Port of AIEQ-Core ExpectedInformationGainPolicy.
  """

  alias Vaos.Ledger.Epistemic.Models

  @type option :: {:limit, pos_integer()}

  @doc """
  Rank actions by expected information gain.

  WARNING: This function calls `GenServer.call/3` on the `ledger` process.
  It must NOT be called from within the Ledger GenServer process itself,
  or it will deadlock. Always call from an external process.
  """
  @spec rank_actions(GenServer.server(), list(option())) :: list(Vaos.Ledger.Epistemic.Models.ActionProposal.t())
  def rank_actions(ledger, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    claims = GenServer.call(ledger, :list_claims, 5_000)

    proposals =
      Enum.flat_map(claims, fn claim ->
        if claim.status == :archived do
          []
        else
          metrics = GenServer.call(ledger, {:claim_metrics, claim.id}, 5_000)
          build_proposals_for_claim(claim, metrics, ledger)
        end
      end)

    proposals
    |> Enum.sort_by(& &1.expected_information_gain, :desc)
    |> Enum.take(limit)
  end

  defp build_proposals_for_claim(claim, metrics, _ledger) do
    uncertainty = metrics["uncertainty"]
    attack_pressure = metrics["open_attack_load"]
    support_signal = Models.clamp(metrics["support_score"])
    contradict_signal = Models.clamp(metrics["contradict_score"])
    evidence_count = metrics["evidence_count"]
    series_failure_pressure = autoresearch_failure_pressure(metrics)
    series_momentum = autoresearch_momentum(metrics)
    series_plateau = autoresearch_plateau(metrics)

    proposals = []

    # Run experiment proposal
    experiment_score =
      Models.clamp(
        0.40 * uncertainty +
          0.25 * claim.novelty +
          0.20 * claim.falsifiability +
          0.15 * attack_pressure +
          if(evidence_count == 0, do: 0.10, else: 0.0) -
          0.22 * series_failure_pressure +
          0.08 * series_momentum
      )

    experiment_proposal =
      Models.ActionProposal.new(
        claim_id: claim.id,
        claim_title: claim.title,
        action_type: :run_experiment,
        expected_information_gain: experiment_score,
        priority: priority(experiment_score),
        reason:
          "Novel claim remains unresolved; a bounded experiment should move " <>
            "belief faster than more debate."
      )

    proposals = [experiment_proposal | proposals]

    # Challenge assumption proposal
    proposals =
      if metrics["highest_risk_assumption_id"] != "" do
        assumption_score =
          Models.clamp(
            0.50 * metrics["highest_risk_assumption_risk"] +
              0.25 * uncertainty +
              0.15 * claim.novelty +
              0.10 * attack_pressure +
              0.14 * series_failure_pressure +
              if(series_plateau, do: 0.10, else: 0.0)
          )

        assumption_proposal =
          Models.ActionProposal.new(
            claim_id: claim.id,
            claim_title: claim.title,
            action_type: :challenge_assumption,
            expected_information_gain: assumption_score,
            priority: priority(assumption_score),
            reason:
              "The riskiest assumption is a likely epistemic bottleneck; " <>
                "stress-testing it could collapse or strengthen claim."
          )

        [assumption_proposal | proposals]
      else
        proposals
      end

    # Triage attack proposal
    proposals =
      if metrics["open_attack_count"] > 0 do
        attack_score =
          Models.clamp(
            0.55 * attack_pressure +
              0.20 * uncertainty +
              0.15 * claim.falsifiability +
              0.10 * claim.novelty
          )

        attack_proposal =
          Models.ActionProposal.new(
            claim_id: claim.id,
            claim_title: claim.title,
            action_type: :triage_attack,
            expected_information_gain: attack_score,
            priority: priority(attack_score),
            reason:
              "Open attacks are unresolved falsifiers. Closing them converts " <>
                "generic skepticism into explicit evidence."
          )

        [attack_proposal | proposals]
      else
        proposals
      end

    # Collect counterevidence proposal
    proposals =
      if evidence_count > 0 do
        counterevidence_score =
          Models.clamp(
            0.40 * abs(support_signal - contradict_signal) +
              0.25 * claim.novelty +
              0.20 * uncertainty +
              0.15 * claim.falsifiability +
              0.08 * series_failure_pressure +
              if(series_plateau, do: 0.10, else: 0.0)
          )

        counterevidence_proposal =
          Models.ActionProposal.new(
            claim_id: claim.id,
            claim_title: claim.title,
            action_type: :collect_counterevidence,
            expected_information_gain: counterevidence_score,
            priority: priority(counterevidence_score),
            reason:
              "Current evidence leans in one direction; targeted counterevidence " <>
                "would reduce overfitting to first positive result."
          )

        [counterevidence_proposal | proposals]
      else
        proposals
      end

    # Reproduce result proposal
    proposals =
      if support_signal > 0.55 and evidence_count <= 1 do
        reproduce_score =
          Models.clamp(
            0.45 * support_signal +
              0.25 * claim.novelty +
              0.20 * claim.falsifiability +
              0.10 * uncertainty +
              0.12 * series_momentum -
              0.10 * series_failure_pressure
          )

        reproduce_proposal =
          Models.ActionProposal.new(
            claim_id: claim.id,
            claim_title: claim.title,
            action_type: :reproduce_result,
            expected_information_gain: reproduce_score,
            priority: priority(reproduce_score),
            reason:
              "A single positive result is fragile. Reproduction is fastest " <>
                "way to convert a promising anecdote into evidence."
          )

        [reproduce_proposal | proposals]
      else
        proposals
      end

    Enum.reverse(proposals)
  end

  defp autoresearch_failure_pressure(metrics) do
    run_count = trunc(metrics["autoresearch_series_run_count"])

    if run_count == 0 do
      0.0
    else
      stagnation_pressure =
        Models.clamp(metrics["autoresearch_series_stagnation_run_count"] / max(run_count, 1))

      crash_pressure = Models.clamp(metrics["autoresearch_series_crash_rate"])
      low_yield_pressure = Models.clamp(1.0 - metrics["autoresearch_series_keep_rate"])

      base_pressure =
        Models.clamp(
          0.45 * stagnation_pressure +
            0.35 * crash_pressure +
            0.20 * low_yield_pressure
        )

      branch_count = trunc(Map.get(metrics, "autoresearch_branch_count", 0))
      active_branch_count = trunc(Map.get(metrics, "autoresearch_active_branch_count", 0))

      if branch_count > 0 and active_branch_count > 0 do
        relief = Models.clamp(active_branch_count / branch_count)
        Models.clamp(base_pressure * (1.0 - 0.25 * relief))
      else
        base_pressure
      end
    end
  end

  defp autoresearch_momentum(metrics) do
    run_count = trunc(metrics["autoresearch_series_run_count"])

    if run_count == 0 do
      0.0
    else
      improvement_signal =
        Models.clamp(max(metrics["autoresearch_series_best_improvement_bpb"], 0.0) / 0.005)

      frontier_signal =
        Models.clamp(metrics["autoresearch_series_frontier_improvement_count"] / 3.0)

      branch_count = trunc(Map.get(metrics, "autoresearch_branch_count", 0))
      active_branch_count = trunc(Map.get(metrics, "autoresearch_active_branch_count", 0))

      branch_activity =
        if branch_count > 0 do
          Models.clamp(active_branch_count / branch_count)
        else
          0.0
        end

      Models.clamp(0.60 * improvement_signal + 0.25 * frontier_signal + 0.15 * branch_activity)
    end
  end

  defp autoresearch_plateau(metrics) do
    branch_count = trunc(Map.get(metrics, "autoresearch_branch_count", 0))
    plateau_branch_count = trunc(Map.get(metrics, "autoresearch_plateau_branch_count", 0))
    active_branch_count = trunc(Map.get(metrics, "autoresearch_active_branch_count", 0))

    if branch_count > 0 do
      plateau_branch_count >= branch_count and active_branch_count == 0
    else
      run_count = trunc(metrics["autoresearch_series_run_count"])
      stagnation_count = trunc(metrics["autoresearch_series_stagnation_run_count"])
      best_improvement = metrics["autoresearch_series_best_improvement_bpb"]

      run_count >= 4 and stagnation_count >= 4 and best_improvement <= 0.0005
    end
  end

  defp priority(score) when score >= 0.75, do: "now"
  defp priority(score) when score >= 0.55, do: "next"
  defp priority(_score), do: "watch"
end
