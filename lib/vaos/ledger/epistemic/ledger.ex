defmodule Vaos.Ledger.Epistemic.Ledger do
  @moduledoc """
  GenServer-based epistemic ledger with JSON persistence.
  Persistent claim/evidence graph for automated research workflows.

  Port of AIEQ-Core EpistemicLedger.
  """

  use GenServer
  require Logger

  alias Vaos.Ledger.Epistemic.Models

  @schema_version 7

  # Client API

  @doc """
  Start the ledger server.
  """
  def start_link(opts) do
    path = Keyword.fetch!(opts, :path)
    GenServer.start_link(__MODULE__, path, name: __MODULE__)
  end

  @doc """
  Stop the ledger server.
  """
  def stop do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Get the ledger state (for testing/debugging).
  """
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc """
  Save the ledger to disk.
  """
  def save do
    GenServer.call(__MODULE__, :save)
  end

  @doc """
  List all claims.
  """
  def list_claims do
    GenServer.call(__MODULE__, :list_claims)
  end

  @doc """
  Get a claim by ID.
  """
  def get_claim(claim_id) do
    GenServer.call(__MODULE__, {:get_claim, claim_id})
  end

  @doc """
  Get a claim snapshot with all related entities.
  """
  def claim_snapshot(claim_id) do
    GenServer.call(__MODULE__, {:claim_snapshot, claim_id})
  end

  @doc """
  Get summary rows for all claims.
  """
  def summary_rows do
    GenServer.call(__MODULE__, :summary_rows)
  end

  @doc """
  Add a new claim.
  """
  def add_claim(attrs) do
    GenServer.call(__MODULE__, {:add_claim, attrs})
  end

  @doc """
  Add an assumption to a claim.
  """
  def add_assumption(attrs) do
    GenServer.call(__MODULE__, {:add_assumption, attrs})
  end

  @doc """
  Add evidence to a claim.
  """
  def add_evidence(attrs) do
    GenServer.call(__MODULE__, {:add_evidence, attrs})
  end

  @doc """
  Add an attack to a claim.
  """
  def add_attack(attrs) do
    GenServer.call(__MODULE__, {:add_attack, attrs})
  end

  @doc """
  Add an artifact to a claim.
  """
  def add_artifact(attrs) do
    GenServer.call(__MODULE__, {:add_artifact, attrs})
  end

  @doc """
  Register an input artifact.
  """
  def register_input(attrs) do
    GenServer.call(__MODULE__, {:register_input, attrs})
  end

  @doc """
  Add a hypothesis.
  """
  def add_hypothesis(attrs) do
    GenServer.call(__MODULE__, {:add_hypothesis, attrs})
  end

  @doc """
  Add a protocol draft.
  """
  def add_protocol_draft(attrs) do
    GenServer.call(__MODULE__, {:add_protocol_draft, attrs})
  end

  @doc """
  Register a target for mutation.
  """
  def register_target(attrs) do
    GenServer.call(__MODULE__, {:register_target, attrs})
  end

  @doc """
  Register an evaluation suite.
  """
  def register_eval_suite(attrs) do
    GenServer.call(__MODULE__, {:register_eval_suite, attrs})
  end

  @doc """
  Add a mutation candidate.
  """
  def add_mutation_candidate(attrs) do
    GenServer.call(__MODULE__, {:add_mutation_candidate, attrs})
  end

  @doc """
  Record an evaluation run.
  """
  def record_eval_run(attrs) do
    GenServer.call(__MODULE__, {:record_eval_run, attrs})
  end

  @doc """
  Promote a candidate as the winner.
  """
  def promote_candidate(target_id, candidate_id) do
    GenServer.call(__MODULE__, {:promote_candidate, target_id, candidate_id})
  end

  @doc """
  Upsert an artifact (add or update).
  """
  def upsert_artifact(attrs) do
    GenServer.call(__MODULE__, {:upsert_artifact, attrs})
  end

  @doc """
  Get entities for a claim.
  """
  def assumptions_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:assumptions_for_claim, claim_id})
  end

  def evidence_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:evidence_for_claim, claim_id})
  end

  def attacks_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:attacks_for_claim, claim_id})
  end

  def artifacts_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:artifacts_for_claim, claim_id})
  end

  def inputs_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:inputs_for_claim, claim_id})
  end

  def hypotheses_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:hypotheses_for_claim, claim_id})
  end

  def protocols_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:protocols_for_claim, claim_id})
  end

  def targets_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:targets_for_claim, claim_id})
  end

  def eval_suites_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:eval_suites_for_claim, claim_id})
  end

  def mutation_candidates_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:mutation_candidates_for_claim, claim_id})
  end

  def eval_runs_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:eval_runs_for_claim, claim_id})
  end

  def decisions_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:decisions_for_claim, claim_id})
  end

  def executions_for_claim(claim_id) do
    GenServer.call(__MODULE__, {:executions_for_claim, claim_id})
  end

  @doc """
  Get entities by relations.
  """
  def hypotheses_for_input(input_id) do
    GenServer.call(__MODULE__, {:hypotheses_for_input, input_id})
  end

  def protocols_for_input(input_id) do
    GenServer.call(__MODULE__, {:protocols_for_input, input_id})
  end

  def protocols_for_hypothesis(hypothesis_id) do
    GenServer.call(__MODULE__, {:protocols_for_hypothesis, hypothesis_id})
  end

  @doc """
  Get individual entities.
  """
  def get_input(input_id) do
    GenServer.call(__MODULE__, {:get_input, input_id})
  end

  def get_hypothesis(hypothesis_id) do
    GenServer.call(__MODULE__, {:get_hypothesis, hypothesis_id})
  end

  def get_protocol(protocol_id) do
    GenServer.call(__MODULE__, {:get_protocol, protocol_id})
  end

  def get_decision(decision_id) do
    GenServer.call(__MODULE__, {:get_decision, decision_id})
  end

  def get_target(target_id) do
    GenServer.call(__MODULE__, {:get_target, target_id})
  end

  def get_eval_suite(suite_id) do
    GenServer.call(__MODULE__, {:get_eval_suite, suite_id})
  end

  def get_mutation_candidate(candidate_id) do
    GenServer.call(__MODULE__, {:get_mutation_candidate, candidate_id})
  end

  @doc """
  List entities.
  """
  def list_decisions do
    GenServer.call(__MODULE__, :list_decisions)
  end

  def list_executions do
    GenServer.call(__MODULE__, :list_executions)
  end

  def list_inputs do
    GenServer.call(__MODULE__, :list_inputs)
  end

  def list_hypotheses do
    GenServer.call(__MODULE__, :list_hypotheses)
  end

  def list_protocols do
    GenServer.call(__MODULE__, :list_protocols)
  end

  @doc """
  Record a decision.
  """
  def record_decision(proposal, opts \\ []) do
    GenServer.call(__MODULE__, {:record_decision, proposal, opts})
  end

  @doc """
  Record an execution.
  """
  def record_execution(attrs) do
    GenServer.call(__MODULE__, {:record_execution, attrs})
  end

  @doc """
  Link a hypothesis to a claim.
  """
  def link_hypothesis_to_claim(hypothesis_id, claim_id, status \\ :materialized) do
    GenServer.call(__MODULE__, {:link_hypothesis_to_claim, hypothesis_id, claim_id, status})
  end

  @doc """
  Link an input to a claim.
  """
  def link_input_to_claim(input_id, claim_id) do
    GenServer.call(__MODULE__, {:link_input_to_claim, input_id, claim_id})
  end

  @doc """
  Link a protocol to a claim.
  """
  def link_protocol_to_claim(protocol_id, claim_id, status \\ :materialized) do
    GenServer.call(__MODULE__, {:link_protocol_to_claim, protocol_id, claim_id, status})
  end

  @doc """
  Refresh all claims.
  """
  def refresh_all do
    GenServer.call(__MODULE__, :refresh_all)
  end

  @doc """
  Refresh a specific claim.
  """
  def refresh_claim(claim_id) do
    GenServer.call(__MODULE__, {:refresh_claim, claim_id})
  end

  @doc """
  Get claim metrics.
  """
  def claim_metrics(claim_id) do
    GenServer.call(__MODULE__, {:claim_metrics, claim_id})
  end

  # Server Callbacks

  @impl true
  def init(path) do
    state = load_or_init(path)
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:save, _from, state) do
    new_state = persist(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_claims, _from, state) do
    claims =
      state.claims
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, claims, state}
  end

  @impl true
  def handle_call({:get_claim, claim_id}, _from, state) do
    case Map.get(state.claims, claim_id) do
      nil -> {:reply, {:error, :not_found}, state}
      claim -> {:reply, {:ok, claim}, state}
    end
  end

  @impl true
  def handle_call({:claim_snapshot, claim_id}, _from, state) do
    case Map.get(state.claims, claim_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      claim ->
        snapshot = %{
          claim: Models.serialize_struct(claim),
          metrics: claim_metrics(state, claim_id),
          assumptions:
            assumptions_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          evidence:
            evidence_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          attacks:
            attacks_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          artifacts:
            artifacts_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          inputs:
            inputs_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          hypotheses:
            hypotheses_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          protocols:
            protocols_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          targets:
            targets_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          eval_suites:
            eval_suites_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          mutation_candidates:
            mutation_candidates_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          eval_runs:
            eval_runs_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          decisions:
            decisions_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1),
          executions:
            executions_for_claim(state, claim_id)
            |> Enum.map(&Models.serialize_struct/1)
        }

        {:reply, snapshot, state}
    end
  end

  @impl true
  def handle_call(:summary_rows, _from, state) do
    rows =
      state.claims
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)
      |> Enum.map(fn claim ->
        metrics = claim_metrics(state, claim.id)

        %{
          claim_id: claim.id,
          title: claim.title,
          mode: Map.get(claim.metadata, "mode", "") |> String.trim() |> maybe_default("ml_research"),
          status: claim.status,
          confidence: safe_round(claim.confidence, 3),
          uncertainty: safe_round(metrics["uncertainty"], 3),
          evidence_count: metrics["evidence_count"],
          open_attack_count: metrics["open_attack_count"],
          artifact_count: metrics["artifact_count"],
          target_count: metrics["target_count"],
          input_count: metrics["input_count"],
          hypothesis_count: metrics["hypothesis_count"],
          protocol_count: metrics["protocol_count"],
          ready_protocol_count: metrics["ready_protocol_count"],
          eval_suite_count: metrics["eval_suite_count"],
          mutation_candidate_count: metrics["mutation_candidate_count"],
          eval_run_count: metrics["eval_run_count"],
          decision_count: metrics["decision_count"],
          execution_count: metrics["execution_count"],
          novelty: safe_round(claim.novelty, 3),
          falsifiability: safe_round(claim.falsifiability, 3)
        }
      end)

    {:reply, rows, state}
  end

  @impl true
  def handle_call({:add_claim, attrs}, _from, state) do
    base_attrs = [
      title: Keyword.fetch!(attrs, :title),
      statement: Keyword.fetch!(attrs, :statement),
      novelty: Keyword.get(attrs, :novelty, 0.5),
      falsifiability: Keyword.get(attrs, :falsifiability, 0.5),
      tags: Keyword.get(attrs, :tags, []),
      metadata: Keyword.get(attrs, :metadata, %{})
    ]
    base_attrs = if Keyword.has_key?(attrs, :id), do: Keyword.put(base_attrs, :id, attrs[:id]), else: base_attrs
    claim = Models.Claim.new(base_attrs)

    new_state = put_in(state.claims[claim.id], claim) |> persist()
    {:reply, claim, new_state}
  end

  @impl true
  def handle_call({:add_assumption, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        assumption =
        Models.Assumption.new(
          claim_id: claim_id,
          text: Keyword.fetch!(attrs, :text),
          rationale: Keyword.get(attrs, :rationale, ""),
          risk: Keyword.get(attrs, :risk, 0.5),
          tags: Keyword.get(attrs, :tags, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:assumptions, assumption.id], assumption)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | assumption_ids: [assumption.id | c.assumption_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, assumption, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_evidence, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        evidence =
          Models.Evidence.new(
          claim_id: claim_id,
          summary: Keyword.fetch!(attrs, :summary),
          direction: Keyword.get(attrs, :direction, :inconclusive),
          strength: Keyword.get(attrs, :strength, 0.5),
          confidence: Keyword.get(attrs, :confidence, 0.5),
          source_type: Keyword.get(attrs, :source_type, "manual"),
          source_ref: Keyword.get(attrs, :source_ref, ""),
          artifact_paths: Keyword.get(attrs, :artifact_paths, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:evidence, evidence.id], evidence)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | evidence_ids: [evidence.id | c.evidence_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, evidence, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_attack, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        attack =
          Models.Attack.new(
          claim_id: claim_id,
          description: Keyword.fetch!(attrs, :description),
          target_kind: Keyword.get(attrs, :target_kind, "claim"),
          target_id: Keyword.get(attrs, :target_id, ""),
          severity: Keyword.get(attrs, :severity, 0.5),
          status: Keyword.get(attrs, :status, :open),
          resolution: Keyword.get(attrs, :resolution, ""),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:attacks, attack.id], attack)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | attack_ids: [attack.id | c.attack_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, attack, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_artifact, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        artifact =
          Models.Artifact.new(
          claim_id: claim_id,
          kind: Keyword.fetch!(attrs, :kind),
          title: Keyword.fetch!(attrs, :title),
          content: Keyword.get(attrs, :content, ""),
          source_type: Keyword.get(attrs, :source_type, "manual"),
          source_ref: Keyword.get(attrs, :source_ref, ""),
          source_path: Keyword.get(attrs, :source_path, ""),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:artifacts, artifact.id], artifact)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | artifact_ids: [artifact.id | c.artifact_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, artifact, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_input, attrs}, _from, state) do
    input =
      Models.InputArtifact.new(
        title: Keyword.fetch!(attrs, :title),
        input_type: Keyword.fetch!(attrs, :input_type),
        content: Keyword.fetch!(attrs, :content),
        source_type: Keyword.get(attrs, :source_type, "manual"),
        source_ref: Keyword.get(attrs, :source_ref, ""),
        source_path: Keyword.get(attrs, :source_path, ""),
        summary: Keyword.get(attrs, :summary, ""),
        tags: Keyword.get(attrs, :tags, []),
        metadata: Keyword.get(attrs, :metadata, %{}),
        id: Keyword.get(attrs, :id)
      )

    new_state = put_in(state.inputs[input.id], input) |> persist()
    {:reply, input, new_state}
  end

  @impl true
  def handle_call({:add_hypothesis, attrs}, _from, state) do
    input_id = Keyword.fetch!(attrs, :input_id)

    case fetch_input(state, input_id) do
      {:ok, _input} ->
        hypothesis =
        Models.InnovationHypothesis.new(
          input_id: input_id,
          title: Keyword.fetch!(attrs, :title),
          statement: Keyword.fetch!(attrs, :statement),
          summary: Keyword.get(attrs, :summary, ""),
          rationale: Keyword.get(attrs, :rationale, ""),
          recommended_mode: Keyword.get(attrs, :recommended_mode, ""),
          target_type: Keyword.get(attrs, :target_type, ""),
          target_title: Keyword.get(attrs, :target_title, ""),
          target_source_strategy: Keyword.get(attrs, :target_source_strategy, ""),
          mutable_fields: Keyword.get(attrs, :mutable_fields, []),
          suggested_constraints: Keyword.get(attrs, :suggested_constraints, []),
          eval_outline: Keyword.get(attrs, :eval_outline, []),
          leverage: Keyword.get(attrs, :leverage, 0.5),
          testability: Keyword.get(attrs, :testability, 0.5),
          novelty: Keyword.get(attrs, :novelty, 0.5),
          strategic_novelty: Keyword.get(attrs, :strategic_novelty, 0.5),
          domain_differentiation: Keyword.get(attrs, :domain_differentiation, 0.5),
          fork_specificity: Keyword.get(attrs, :fork_specificity, 0.5),
          optimization_readiness: Keyword.get(attrs, :optimization_readiness, 0.5),
          overall_score: Keyword.get(attrs, :overall_score, 0.0),
          status: Keyword.get(attrs, :status, :proposed),
          materialized_claim_id: Keyword.get(attrs, :materialized_claim_id, ""),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

        new_state = put_in(state.hypotheses[hypothesis.id], hypothesis) |> persist()
        {:reply, hypothesis, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_protocol_draft, attrs}, _from, state) do
    input_id = Keyword.fetch!(attrs, :input_id)
    hypothesis_id = Keyword.fetch!(attrs, :hypothesis_id)

    with {:ok, _input} <- fetch_input(state, input_id),
         {:ok, hypothesis} <- fetch_hypothesis(state, hypothesis_id) do
      if hypothesis.input_id != input_id do
        {:reply, {:error, :input_hypothesis_mismatch}, state}
      else
        protocol =
          Models.ProtocolDraft.new(
            input_id: input_id,
            hypothesis_id: hypothesis_id,
            recommended_mode: Keyword.get(attrs, :recommended_mode, ""),
            status: Keyword.get(attrs, :status, :draft),
            artifact_candidates: Keyword.get(attrs, :artifact_candidates, []),
            target_spec: Keyword.get(attrs, :target_spec, %{}),
            eval_plan: Keyword.get(attrs, :eval_plan, %{}),
            baseline_plan: Keyword.get(attrs, :baseline_plan, %{}),
            blockers: Keyword.get(attrs, :blockers, []),
            extraction_confidence: Keyword.get(attrs, :extraction_confidence, 0.0),
            eval_confidence: Keyword.get(attrs, :eval_confidence, 0.0),
            execution_readiness: Keyword.get(attrs, :execution_readiness, 0.0),
            materialized_claim_id: Keyword.get(attrs, :materialized_claim_id, ""),
            metadata: Keyword.get(attrs, :metadata, %{}),
            id: Keyword.get(attrs, :id)
          )

        new_state = put_in(state.protocols[protocol.id], protocol) |> persist()
        {:reply, protocol, new_state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_target, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        target =
          Models.ArtifactTarget.new(
          claim_id: claim_id,
          mode: Keyword.fetch!(attrs, :mode),
          target_type: Keyword.fetch!(attrs, :target_type),
          title: Keyword.fetch!(attrs, :title),
          content: Keyword.get(attrs, :content, ""),
          source_type: Keyword.get(attrs, :source_type, "manual"),
          source_ref: Keyword.get(attrs, :source_ref, ""),
          source_path: Keyword.get(attrs, :source_path, ""),
          mutable_fields: Keyword.get(attrs, :mutable_fields, []),
          invariant_constraints: Keyword.get(attrs, :invariant_constraints, %{}),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:targets, target.id], target)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | target_ids: [target.id | c.target_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, target, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_eval_suite, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)
    target_id = Keyword.fetch!(attrs, :target_id)

    with {:ok, _claim} <- fetch_claim(state, claim_id),
         {:ok, _target} <- fetch_target(state, target_id) do
      suite =
        Models.EvalSuite.new(
          claim_id: claim_id,
          target_id: target_id,
          name: Keyword.fetch!(attrs, :name),
          compatible_target_type: Keyword.fetch!(attrs, :compatible_target_type),
          scoring_method: Keyword.get(attrs, :scoring_method, "binary"),
          aggregation: Keyword.get(attrs, :aggregation, "average"),
          pass_threshold: Keyword.get(attrs, :pass_threshold, 1.0),
          repetitions: Keyword.get(attrs, :repetitions, 1),
          cases: Keyword.get(attrs, :cases, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:eval_suites, suite.id], suite)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | eval_suite_ids: [suite.id | c.eval_suite_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, suite, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_mutation_candidate, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)
    target_id = Keyword.fetch!(attrs, :target_id)

    with {:ok, _claim} <- fetch_claim(state, claim_id),
         {:ok, _target} <- fetch_target(state, target_id) do
      candidate =
        Models.MutationCandidate.new(
          claim_id: claim_id,
          target_id: target_id,
          parent_candidate_id: Keyword.get(attrs, :parent_candidate_id, ""),
          summary: Keyword.fetch!(attrs, :summary),
          content: Keyword.fetch!(attrs, :content),
          source_type: Keyword.get(attrs, :source_type, "manual"),
          source_ref: Keyword.get(attrs, :source_ref, ""),
          source_path: Keyword.get(attrs, :source_path, ""),
          review_status: Keyword.get(attrs, :review_status, :pending),
          review_notes: Keyword.get(attrs, :review_notes, ""),
          artifact_paths: Keyword.get(attrs, :artifact_paths, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:mutation_candidates, candidate.id], candidate)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | mutation_candidate_ids: [candidate.id | c.mutation_candidate_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, candidate, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:record_eval_run, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)
    target_id = Keyword.fetch!(attrs, :target_id)
    suite_id = Keyword.fetch!(attrs, :suite_id)
    candidate_id = Keyword.fetch!(attrs, :candidate_id)

    with {:ok, _claim} <- fetch_claim(state, claim_id),
         {:ok, _target} <- fetch_target(state, target_id),
         {:ok, _suite} <- fetch_eval_suite(state, suite_id),
         {:ok, _candidate} <- fetch_mutation_candidate(state, candidate_id) do
      eval_run =
        Models.EvalRun.new(
          claim_id: claim_id,
          target_id: target_id,
          suite_id: suite_id,
          candidate_id: candidate_id,
          case_id: Keyword.fetch!(attrs, :case_id),
          run_index: Keyword.fetch!(attrs, :run_index),
          score: Keyword.fetch!(attrs, :score),
          passed: Keyword.fetch!(attrs, :passed),
          raw_output: Keyword.get(attrs, :raw_output, ""),
          runtime_seconds: Keyword.get(attrs, :runtime_seconds),
          cost_estimate_usd: Keyword.get(attrs, :cost_estimate_usd),
          artifact_paths: Keyword.get(attrs, :artifact_paths, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:eval_runs, eval_run.id], eval_run)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | eval_run_ids: [eval_run.id | c.eval_run_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, eval_run, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:promote_candidate, target_id, candidate_id}, _from, state) do
    with {:ok, target} <- fetch_target(state, target_id),
         {:ok, _candidate} <- fetch_mutation_candidate(state, candidate_id) do
      updated_target =
        target
        |> Map.put(:promoted_candidate_id, candidate_id)
        |> Map.put(:updated_at, Models.utc_now())

      new_state =
        state
        |> put_in([:targets, target_id], updated_target)
        |> persist()

      {:reply, updated_target, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:upsert_artifact, attrs}, _from, state) do
    claim_id = Keyword.fetch!(attrs, :claim_id)
    kind = Keyword.fetch!(attrs, :kind)
    source_path = Keyword.get(attrs, :source_path, "")

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        existing =
        artifacts_for_claim(state, claim_id)
        |> Enum.find(fn a -> a.kind == kind and a.source_path == source_path end)

      result =
        if existing do
          updated =
            existing
            |> Map.put(:title, Keyword.fetch!(attrs, :title))
            |> Map.put(:content, Keyword.get(attrs, :content, ""))
            |> Map.put(:source_type, Keyword.get(attrs, :source_type, "manual"))
            |> Map.put(:source_ref, Keyword.get(attrs, :source_ref, ""))
            |> Map.put(:source_path, source_path)
            |> Map.put(:updated_at, Models.utc_now())
            |> Map.put(:metadata, Keyword.get(attrs, :metadata, %{}))

          new_state =
            state
            |> put_in([:artifacts, existing.id], updated)
            |> persist()

          {:reply, updated, new_state}
        else
          artifact =
            Models.Artifact.new(
              claim_id: claim_id,
              kind: kind,
              title: Keyword.fetch!(attrs, :title),
              content: Keyword.get(attrs, :content, ""),
              source_type: Keyword.get(attrs, :source_type, "manual"),
              source_ref: Keyword.get(attrs, :source_ref, ""),
              source_path: source_path,
              metadata: Keyword.get(attrs, :metadata, %{})
            )

          new_state =
            state
            |> put_in([:artifacts, artifact.id], artifact)
            |> then(fn s ->

              c = Map.get(s.claims, claim_id)

              c = %{c | artifact_ids: [artifact.id | c.artifact_ids]}

              %{s | claims: Map.put(s.claims, claim_id, c)}

            end)
            |> persist()

          {:reply, artifact, new_state}
        end

        result

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  # Implement remaining handle_call clauses for getters and list operations
  @impl true
  def handle_call({:assumptions_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.assumption_ids
        |> Enum.map(&Map.get(state.assumptions, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:evidence_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.evidence_ids
        |> Enum.map(&Map.get(state.evidence, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:attacks_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.attack_ids
        |> Enum.map(&Map.get(state.attacks, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:artifacts_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.artifact_ids
        |> Enum.map(&Map.get(state.artifacts, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:inputs_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.input_ids
        |> Enum.map(&Map.get(state.inputs, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:hypotheses_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.hypothesis_ids
        |> Enum.map(&Map.get(state.hypotheses, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:protocols_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.protocol_ids
        |> Enum.map(&Map.get(state.protocols, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:targets_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.target_ids
        |> Enum.map(&Map.get(state.targets, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:eval_suites_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.eval_suite_ids
        |> Enum.map(&Map.get(state.eval_suites, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:mutation_candidates_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.mutation_candidate_ids
        |> Enum.map(&Map.get(state.mutation_candidates, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:eval_runs_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.eval_run_ids
        |> Enum.map(&Map.get(state.eval_runs, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:decisions_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.decision_ids
        |> Enum.map(&Map.get(state.decisions, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:executions_for_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
      result =
        claim.execution_ids
        |> Enum.map(&Map.get(state.executions, &1))
        |> Enum.reject(&is_nil/1)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:hypotheses_for_input, input_id}, _from, state) do
    case fetch_input(state, input_id) do
      {:ok, _input} ->
      result =
        state.hypotheses
        |> Map.values()
        |> Enum.filter(&(&1.input_id == input_id))
        |> Enum.sort_by(& &1.created_at)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:protocols_for_input, input_id}, _from, state) do
    case fetch_input(state, input_id) do
      {:ok, _input} ->
      result =
        state.protocols
        |> Map.values()
        |> Enum.filter(&(&1.input_id == input_id))
        |> Enum.sort_by(& &1.created_at)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:protocols_for_hypothesis, hypothesis_id}, _from, state) do
    case fetch_hypothesis(state, hypothesis_id) do
      {:ok, _hypothesis} ->
      result =
        state.protocols
        |> Map.values()
        |> Enum.filter(&(&1.hypothesis_id == hypothesis_id))
        |> Enum.sort_by(& &1.created_at)

      {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_input, input_id}, _from, state) do
    case Map.get(state.inputs, input_id) do
      nil -> {:reply, {:error, :not_found}, state}
      input -> {:reply, {:ok, input}, state}
    end
  end

  @impl true
  def handle_call({:get_hypothesis, hypothesis_id}, _from, state) do
    case Map.get(state.hypotheses, hypothesis_id) do
      nil -> {:reply, {:error, :not_found}, state}
      hypothesis -> {:reply, {:ok, hypothesis}, state}
    end
  end

  @impl true
  def handle_call({:get_protocol, protocol_id}, _from, state) do
    case Map.get(state.protocols, protocol_id) do
      nil -> {:reply, {:error, :not_found}, state}
      protocol -> {:reply, {:ok, protocol}, state}
    end
  end

  @impl true
  def handle_call({:get_decision, decision_id}, _from, state) do
    case Map.get(state.decisions, decision_id) do
      nil -> {:reply, {:error, :not_found}, state}
      decision -> {:reply, {:ok, decision}, state}
    end
  end

  @impl true
  def handle_call({:get_target, target_id}, _from, state) do
    case Map.get(state.targets, target_id) do
      nil -> {:reply, {:error, :not_found}, state}
      target -> {:reply, {:ok, target}, state}
    end
  end

  @impl true
  def handle_call({:get_eval_suite, suite_id}, _from, state) do
    case Map.get(state.eval_suites, suite_id) do
      nil -> {:reply, {:error, :not_found}, state}
      suite -> {:reply, {:ok, suite}, state}
    end
  end

  @impl true
  def handle_call({:get_mutation_candidate, candidate_id}, _from, state) do
    case Map.get(state.mutation_candidates, candidate_id) do
      nil -> {:reply, {:error, :not_found}, state}
      candidate -> {:reply, {:ok, candidate}, state}
    end
  end

  @impl true
  def handle_call(:list_decisions, _from, state) do
    result =
      state.decisions
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_executions, _from, state) do
    result =
      state.executions
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_inputs, _from, state) do
    result =
      state.inputs
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_hypotheses, _from, state) do
    result =
      state.hypotheses
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_protocols, _from, state) do
    result =
      state.protocols
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:record_decision, proposal, opts}, _from, state) do
    record =
      Models.DecisionRecord.new(
        claim_id: proposal.claim_id,
        claim_title: proposal.claim_title,
        action_type: proposal.action_type,
        executor: proposal.executor,
        mode: proposal.mode,
        stage: proposal.stage,
        priority: proposal.priority,
        expected_information_gain: proposal.expected_information_gain,
        reason: proposal.reason,
        command_hint: proposal.command_hint,
        metadata: Keyword.get(opts, :metadata, %{}),
        id: Keyword.get(opts, :id)
      )

    new_state =
      state
      |> put_in([:decisions, record.id], record)
      |> then(fn s ->
        if Map.has_key?(s.claims, record.claim_id) do
          update_claim_field(s, record.claim_id, :decision_ids, record.id)
        else
          s
        end
      end)
      |> persist()

    {:reply, record, new_state}
  end

  @impl true
  def handle_call({:record_execution, attrs}, _from, state) do
    decision_id = Keyword.get(attrs, :decision_id, "")

    {claim_id, claim_title, action_type, executor, mode} =
      if decision_id != "" do
        {:ok, decision} = fetch_decision(state, decision_id)

        {
          Keyword.get(attrs, :claim_id, decision.claim_id),
          Keyword.get(attrs, :claim_title, decision.claim_title),
          Keyword.get(attrs, :action_type, decision.action_type),
          Keyword.get(attrs, :executor, decision.executor),
          Keyword.get(attrs, :mode, decision.mode)
        }
      else
        {
          Keyword.fetch!(attrs, :claim_id),
          Keyword.get(attrs, :claim_title, ""),
          Keyword.fetch!(attrs, :action_type),
          Keyword.get(attrs, :executor, :manual),
          Keyword.get(attrs, :mode, "")
        }
      end

    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        final_claim_title =
        if claim_title == "" do
          case Map.get(state.claims, claim_id) do
            nil -> ""
            c -> c.title
          end
        else
          claim_title
        end

      record =
        Models.ExecutionRecord.new(
          decision_id: decision_id,
          claim_id: claim_id,
          claim_title: final_claim_title,
          action_type: action_type,
          executor: executor,
          status: Keyword.fetch!(attrs, :status),
          mode: mode,
          notes: Keyword.get(attrs, :notes, ""),
          runtime_seconds: Keyword.get(attrs, :runtime_seconds),
          cost_estimate_usd: Keyword.get(attrs, :cost_estimate_usd),
          artifact_quality: Keyword.get(attrs, :artifact_quality),
          artifact_paths: Keyword.get(attrs, :artifact_paths, []),
          metadata: Keyword.get(attrs, :metadata, %{}),
          id: Keyword.get(attrs, :id)
        )

      new_state =
        state
        |> put_in([:executions, record.id], record)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | execution_ids: [record.id | c.execution_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

        {:reply, record, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:link_hypothesis_to_claim, hypothesis_id, claim_id, status}, _from, state) do
    with {:ok, hypothesis} <- fetch_hypothesis(state, hypothesis_id),
         {:ok, _claim} <- fetch_claim(state, claim_id) do
      updated_hypothesis =
        hypothesis
        |> Map.put(:materialized_claim_id, claim_id)
        |> Map.put(:status, status)
        |> Map.put(:updated_at, Models.utc_now())

      new_state =
        state
        |> put_in([:hypotheses, hypothesis_id], updated_hypothesis)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | hypothesis_ids: [hypothesis_id | c.hypothesis_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, updated_hypothesis, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:link_input_to_claim, input_id, claim_id}, _from, state) do
    with {:ok, input} <- fetch_input(state, input_id),
         {:ok, _claim} <- fetch_claim(state, claim_id) do
      updated_input =
        if claim_id in input.linked_claim_ids do
          input
        else
          input
          |> Map.put(:linked_claim_ids, [claim_id | input.linked_claim_ids])
          |> Map.put(:updated_at, Models.utc_now())
        end

      new_state =
        state
        |> put_in([:inputs, input_id], updated_input)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | input_ids: [input_id | c.input_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, updated_input, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:link_protocol_to_claim, protocol_id, claim_id, status}, _from, state) do
    with {:ok, protocol} <- fetch_protocol(state, protocol_id),
         {:ok, _claim} <- fetch_claim(state, claim_id) do
      updated_protocol =
        protocol
        |> Map.put(:materialized_claim_id, claim_id)
        |> Map.put(:status, status)
        |> Map.put(:updated_at, Models.utc_now())

      new_state =
        state
        |> put_in([:protocols, protocol_id], updated_protocol)
        |> then(fn s ->

          c = Map.get(s.claims, claim_id)

          c = %{c | protocol_ids: [protocol_id | c.protocol_ids]}

          %{s | claims: Map.put(s.claims, claim_id, c)}

        end)
        |> persist()

      {:reply, updated_protocol, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:refresh_all, _from, state) do
    new_state = refresh_all_in_state(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:refresh_claim, claim_id}, _from, state) do
    case fetch_claim(state, claim_id) do
      {:ok, _claim} ->
        new_state = refresh_claim_in_state(state, claim_id)
        metrics = claim_metrics(new_state, claim_id)
        {:reply, metrics, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:claim_metrics, claim_id}, _from, state) do
    metrics = claim_metrics(state, claim_id)
    {:reply, metrics, state}
  end

  # Helper functions


  # Safely round a number, converting integers to float first
  defp safe_round(value, decimals) when is_float(value), do: Float.round(value, decimals)
  defp safe_round(value, decimals) when is_integer(value), do: Float.round(value * 1.0, decimals)
  defp safe_round(value, _decimals), do: value

  defp load_or_init(path) do
    if File.exists?(path) do
      load_from_file(path)
    else
      %{
        path: path,
        claims: %{},
        assumptions: %{},
        evidence: %{},
        attacks: %{},
        artifacts: %{},
        inputs: %{},
        hypotheses: %{},
        protocols: %{},
        targets: %{},
        eval_suites: %{},
        mutation_candidates: %{},
        eval_runs: %{},
        decisions: %{},
        executions: %{}
      }
    end
  end

  defp load_from_file(path) do
    payload =
      path
      |> File.read!()
      |> Jason.decode!()

    %{
      path: path,
      claims:
        Map.new(payload["claims"] || [], fn raw ->
          {raw["id"], deserialize_claim(raw)}
        end),
      assumptions:
        Map.new(payload["assumptions"] || [], fn raw ->
          {raw["id"], deserialize_assumption(raw)}
        end),
      evidence:
        Map.new(payload["evidence"] || [], fn raw ->
          {raw["id"], deserialize_evidence(raw)}
        end),
      attacks:
        Map.new(payload["attacks"] || [], fn raw ->
          {raw["id"], deserialize_attack(raw)}
        end),
      artifacts:
        Map.new(payload["artifacts"] || [], fn raw ->
          {raw["id"], deserialize_artifact(raw)}
        end),
      inputs:
        Map.new(payload["inputs"] || [], fn raw ->
          {raw["id"], deserialize_input(raw)}
        end),
      hypotheses:
        Map.new(payload["hypotheses"] || [], fn raw ->
          {raw["id"], deserialize_hypothesis(raw)}
        end),
      protocols:
        Map.new(payload["protocols"] || [], fn raw ->
          {raw["id"], deserialize_protocol(raw)}
        end),
      targets:
        Map.new(payload["targets"] || [], fn raw ->
          {raw["id"], deserialize_target(raw)}
        end),
      eval_suites:
        Map.new(payload["eval_suites"] || [], fn raw ->
          {raw["id"], deserialize_eval_suite(raw)}
        end),
      mutation_candidates:
        Map.new(payload["mutation_candidates"] || [], fn raw ->
          {raw["id"], deserialize_mutation_candidate(raw)}
        end),
      eval_runs:
        Map.new(payload["eval_runs"] || [], fn raw ->
          {raw["id"], deserialize_eval_run(raw)}
        end),
      decisions:
        Map.new(payload["decisions"] || [], fn raw ->
          {raw["id"], deserialize_decision(raw)}
        end),
      executions:
        Map.new(payload["executions"] || [], fn raw ->
          {raw["id"], deserialize_execution(raw)}
        end)
    }
    |> rebuild_indexes()
  end

  defp persist(state) do
    state = refresh_all_in_state(state)

    payload = %{
      schema_version: @schema_version,
      saved_at: Models.utc_now(),
      claims:
        state.claims
        |> Map.values()
        |> Enum.map(&Models.serialize_struct/1),
      assumptions:
        state.assumptions
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      evidence:
        state.evidence
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      attacks:
        state.attacks
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      artifacts:
        state.artifacts
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      inputs:
        state.inputs
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      hypotheses:
        state.hypotheses
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      protocols:
        state.protocols
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      targets:
        state.targets
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      eval_suites:
        state.eval_suites
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      mutation_candidates:
        state.mutation_candidates
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      eval_runs:
        state.eval_runs
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      decisions:
        state.decisions
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1),
      executions:
        state.executions
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&Models.serialize_struct/1)
    }

    File.mkdir_p!(Path.dirname(state.path))
    File.write!(state.path, Jason.encode!(payload, pretty: true) <> "\n")

    state
  end

  # Deserialization helpers
  defp deserialize_claim(raw) do
    Models.Claim.new(
      id: raw["id"],
      title: raw["title"],
      statement: raw["statement"],
      status: String.to_existing_atom(raw["status"] || "proposed"),
      novelty: raw["novelty"],
      falsifiability: raw["falsifiability"],
      confidence: raw["confidence"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      tags: raw["tags"] || [],
      assumption_ids: raw["assumption_ids"] || [],
      evidence_ids: raw["evidence_ids"] || [],
      attack_ids: raw["attack_ids"] || [],
      artifact_ids: raw["artifact_ids"] || [],
      decision_ids: raw["decision_ids"] || [],
      execution_ids: raw["execution_ids"] || [],
      target_ids: raw["target_ids"] || [],
      eval_suite_ids: raw["eval_suite_ids"] || [],
      mutation_candidate_ids: raw["mutation_candidate_ids"] || [],
      eval_run_ids: raw["eval_run_ids"] || [],
      input_ids: raw["input_ids"] || [],
      hypothesis_ids: raw["hypothesis_ids"] || [],
      protocol_ids: raw["protocol_ids"] || [],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_assumption(raw) do
    Models.Assumption.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      text: raw["text"],
      rationale: raw["rationale"],
      risk: raw["risk"],
      created_at: raw["created_at"],
      tags: raw["tags"] || [],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_evidence(raw) do
    Models.Evidence.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      summary: raw["summary"],
      direction: String.to_existing_atom(raw["direction"] || "inconclusive"),
      strength: raw["strength"],
      confidence: raw["confidence"],
      source_type: raw["source_type"],
      source_ref: raw["source_ref"],
      artifact_paths: raw["artifact_paths"] || [],
      created_at: raw["created_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_attack(raw) do
    Models.Attack.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      description: raw["description"],
      target_kind: raw["target_kind"],
      target_id: raw["target_id"],
      severity: raw["severity"],
      status: String.to_existing_atom(raw["status"] || "open"),
      created_at: raw["created_at"],
      resolution: raw["resolution"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_artifact(raw) do
    Models.Artifact.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      kind: String.to_existing_atom(raw["kind"] || "method"),
      title: raw["title"],
      content: raw["content"],
      source_type: raw["source_type"],
      source_ref: raw["source_ref"],
      source_path: raw["source_path"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_input(raw) do
    Models.InputArtifact.new(
      id: raw["id"],
      title: raw["title"],
      input_type: raw["input_type"],
      content: raw["content"],
      source_type: raw["source_type"],
      source_ref: raw["source_ref"],
      source_path: raw["source_path"],
      summary: raw["summary"],
      linked_claim_ids: raw["linked_claim_ids"] || [],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      tags: raw["tags"] || [],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_hypothesis(raw) do
    Models.InnovationHypothesis.new(
      id: raw["id"],
      input_id: raw["input_id"],
      title: raw["title"],
      statement: raw["statement"],
      summary: raw["summary"],
      rationale: raw["rationale"],
      recommended_mode: raw["recommended_mode"],
      target_type: raw["target_type"],
      target_title: raw["target_title"],
      target_source_strategy: raw["target_source_strategy"],
      mutable_fields: raw["mutable_fields"] || [],
      suggested_constraints: raw["suggested_constraints"] || [],
      eval_outline: raw["eval_outline"] || [],
      leverage: raw["leverage"],
      testability: raw["testability"],
      novelty: raw["novelty"],
      strategic_novelty: raw["strategic_novelty"],
      domain_differentiation: raw["domain_differentiation"],
      fork_specificity: raw["fork_specificity"],
      optimization_readiness: raw["optimization_readiness"],
      overall_score: raw["overall_score"],
      status: String.to_existing_atom(raw["status"] || "proposed"),
      materialized_claim_id: raw["materialized_claim_id"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_protocol(raw) do
    Models.ProtocolDraft.new(
      id: raw["id"],
      input_id: raw["input_id"],
      hypothesis_id: raw["hypothesis_id"],
      recommended_mode: raw["recommended_mode"],
      status: String.to_existing_atom(raw["status"] || "draft"),
      artifact_candidates: raw["artifact_candidates"] || [],
      target_spec: raw["target_spec"] || %{},
      eval_plan: raw["eval_plan"] || %{},
      baseline_plan: raw["baseline_plan"] || %{},
      blockers: raw["blockers"] || [],
      extraction_confidence: raw["extraction_confidence"],
      eval_confidence: raw["eval_confidence"],
      execution_readiness: raw["execution_readiness"],
      materialized_claim_id: raw["materialized_claim_id"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_target(raw) do
    Models.ArtifactTarget.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      mode: raw["mode"],
      target_type: raw["target_type"],
      title: raw["title"],
      content: raw["content"],
      source_type: raw["source_type"],
      source_ref: raw["source_ref"],
      source_path: raw["source_path"],
      mutable_fields: raw["mutable_fields"] || [],
      invariant_constraints: raw["invariant_constraints"] || %{},
      promoted_candidate_id: raw["promoted_candidate_id"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_eval_suite(raw) do
    Models.EvalSuite.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      target_id: raw["target_id"],
      name: raw["name"],
      compatible_target_type: raw["compatible_target_type"],
      scoring_method: raw["scoring_method"],
      aggregation: raw["aggregation"],
      pass_threshold: raw["pass_threshold"],
      repetitions: raw["repetitions"],
      cases: raw["cases"] || [],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_mutation_candidate(raw) do
    Models.MutationCandidate.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      target_id: raw["target_id"],
      parent_candidate_id: raw["parent_candidate_id"],
      summary: raw["summary"],
      content: raw["content"],
      source_type: raw["source_type"],
      source_ref: raw["source_ref"],
      source_path: raw["source_path"],
      review_status: String.to_existing_atom(raw["review_status"] || "pending"),
      review_notes: raw["review_notes"],
      created_at: raw["created_at"],
      updated_at: raw["updated_at"],
      artifact_paths: raw["artifact_paths"] || [],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_eval_run(raw) do
    Models.EvalRun.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      target_id: raw["target_id"],
      suite_id: raw["suite_id"],
      candidate_id: raw["candidate_id"],
      case_id: raw["case_id"],
      run_index: raw["run_index"],
      score: raw["score"],
      passed: raw["passed"],
      raw_output: raw["raw_output"],
      runtime_seconds: raw["runtime_seconds"],
      cost_estimate_usd: raw["cost_estimate_usd"],
      artifact_paths: raw["artifact_paths"] || [],
      created_at: raw["created_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_decision(raw) do
    Models.DecisionRecord.new(
      id: raw["id"],
      claim_id: raw["claim_id"],
      claim_title: raw["claim_title"],
      action_type: String.to_existing_atom(raw["action_type"]),
      executor: String.to_existing_atom(raw["executor"]),
      mode: raw["mode"],
      stage: raw["stage"],
      priority: raw["priority"],
      expected_information_gain: raw["expected_information_gain"],
      reason: raw["reason"],
      command_hint: raw["command_hint"],
      created_at: raw["created_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp deserialize_execution(raw) do
    Models.ExecutionRecord.new(
      id: raw["id"],
      decision_id: raw["decision_id"],
      claim_id: raw["claim_id"],
      claim_title: raw["claim_title"],
      action_type: String.to_existing_atom(raw["action_type"]),
      executor: String.to_existing_atom(raw["executor"]),
      status: String.to_existing_atom(raw["status"]),
      mode: raw["mode"],
      notes: raw["notes"],
      runtime_seconds: raw["runtime_seconds"],
      cost_estimate_usd: raw["cost_estimate_usd"],
      artifact_quality: raw["artifact_quality"],
      artifact_paths: raw["artifact_paths"] || [],
      created_at: raw["created_at"],
      metadata: raw["metadata"] || %{}
    )
  end

  defp rebuild_indexes(state) do
    # Clear all claim indexes
    state =
      Enum.reduce(state.claims, state, fn {id, claim}, acc ->
        cleared = %{claim |
          assumption_ids: [],
          evidence_ids: [],
          attack_ids: [],
          artifact_ids: [],
          input_ids: [],
          hypothesis_ids: [],
          protocol_ids: [],
          target_ids: [],
          eval_suite_ids: [],
          mutation_candidate_ids: [],
          eval_run_ids: [],
          decision_ids: [],
          execution_ids: []
        }
        %{acc | claims: Map.put(acc.claims, id, cleared)}
      end)

    # Rebuild indexes - use struct update syntax instead of update_in/Access
    state = Enum.reduce(state.assumptions, state, fn {_id, assumption}, acc ->
      update_claim_field(acc, assumption.claim_id, :assumption_ids, assumption.id)
    end)

    state = Enum.reduce(state.evidence, state, fn {_id, evidence}, acc ->
      update_claim_field(acc, evidence.claim_id, :evidence_ids, evidence.id)
    end)

    state = Enum.reduce(state.attacks, state, fn {_id, attack}, acc ->
      update_claim_field(acc, attack.claim_id, :attack_ids, attack.id)
    end)

    state = Enum.reduce(state.artifacts, state, fn {_id, artifact}, acc ->
      update_claim_field(acc, artifact.claim_id, :artifact_ids, artifact.id)
    end)

    state = Enum.reduce(state.inputs, state, fn {_id, input}, acc ->
      Enum.reduce(input.linked_claim_ids, acc, fn claim_id, inner_acc ->
        update_claim_field(inner_acc, claim_id, :input_ids, input.id)
      end)
    end)

    state = Enum.reduce(state.hypotheses, state, fn {_id, hypothesis}, acc ->
      update_claim_field(acc, hypothesis.materialized_claim_id, :hypothesis_ids, hypothesis.id)
    end)

    state = Enum.reduce(state.protocols, state, fn {_id, protocol}, acc ->
      update_claim_field(acc, protocol.materialized_claim_id, :protocol_ids, protocol.id)
    end)

    state = Enum.reduce(state.targets, state, fn {_id, target}, acc ->
      update_claim_field(acc, target.claim_id, :target_ids, target.id)
    end)

    state = Enum.reduce(state.eval_suites, state, fn {_id, suite}, acc ->
      update_claim_field(acc, suite.claim_id, :eval_suite_ids, suite.id)
    end)

    state = Enum.reduce(state.mutation_candidates, state, fn {_id, candidate}, acc ->
      update_claim_field(acc, candidate.claim_id, :mutation_candidate_ids, candidate.id)
    end)

    state = Enum.reduce(state.eval_runs, state, fn {_id, eval_run}, acc ->
      update_claim_field(acc, eval_run.claim_id, :eval_run_ids, eval_run.id)
    end)

    state = Enum.reduce(state.decisions, state, fn {_id, decision}, acc ->
      update_claim_field(acc, decision.claim_id, :decision_ids, decision.id)
    end)

    Enum.reduce(state.executions, state, fn {_id, execution}, acc ->
      update_claim_field(acc, execution.claim_id, :execution_ids, execution.id)
    end)
  end

  # Helper to safely prepend an ID to a claim's list field without Access behaviour
  defp update_claim_field(state, claim_id, field, new_id) do
    case Map.get(state.claims, claim_id) do
      nil -> state
      claim ->
        updated = Map.update!(claim, field, fn ids -> [new_id | ids] end)
        %{state | claims: Map.put(state.claims, claim_id, updated)}
    end
  end

  defp refresh_all_in_state(state) do
    state = rebuild_indexes(state)
    Enum.reduce(state.claims, state, fn {claim_id, _claim}, acc ->
      refresh_claim_in_state(acc, claim_id)
    end)
  end

  defp refresh_claim_in_state(state, claim_id) do
    metrics = claim_metrics(state, claim_id)

    claim = Map.get(state.claims, claim_id)
    if is_nil(claim) do
      state
    else
      updated_status =
        if claim.status != :archived do
          derive_status(claim, metrics)
        else
          claim.status
        end

      updated_claim =
        claim
        |> Map.put(:status, updated_status)
        |> Map.put(:confidence, metrics["belief"])
        |> Map.put(:updated_at, Models.utc_now())

      %{state | claims: Map.put(state.claims, claim_id, updated_claim)}
    end
  end

  # Claim metrics calculation - extracted from Python version
  defp claim_metrics(state, claim_id) do
    claim = get_in(state, [:claims, claim_id])

    if is_nil(claim) do
      %{
        "belief" => 0.0,
        "uncertainty" => 1.0,
        "support_score" => 0.0,
        "contradict_score" => 0.0,
        "inconclusive_score" => 0.0,
        "evidence_weight" => 0.0,
        "evidence_count" => 0,
        "open_attack_count" => 0,
        "open_attack_load" => 0.0,
        "artifact_count" => 0,
        "input_count" => 0,
        "hypothesis_count" => 0,
        "protocol_count" => 0,
        "ready_protocol_count" => 0,
        "method_artifact_count" => 0,
        "paper_artifact_count" => 0,
        "target_count" => 0,
        "eval_suite_count" => 0,
        "mutation_candidate_count" => 0,
        "eval_run_count" => 0,
        "reviewed_candidate_count" => 0,
        "approved_candidate_count" => 0,
        "promoted_candidate_count" => 0,
        "optimization_best_candidate_id" => "",
        "optimization_best_score" => 0.0,
        "optimization_average_pass_rate" => 0.0,
        "optimization_threshold_met" => false,
        "optimization_stagnation_candidate_count" => 0,
        "assumption_risk" => 0.0,
        "decision_count" => 0,
        "execution_count" => 0,
        "failed_execution_count" => 0,
        "successful_execution_count" => 0,
        "total_runtime_seconds" => 0.0,
        "failed_runtime_seconds" => 0.0,
        "total_cost_usd" => 0.0,
        "failed_cost_usd" => 0.0,
        "average_artifact_quality" => 0.0,
        "highest_risk_assumption_id" => "",
        "highest_risk_assumption_risk" => 0.0,
        "autoresearch_series_run_count" => 0,
        "autoresearch_series_keep_rate" => 0.0,
        "autoresearch_series_crash_rate" => 0.0,
        "autoresearch_series_frontier_improvement_count" => 0,
        "autoresearch_series_stagnation_run_count" => 0,
        "autoresearch_series_best_improvement_bpb" => 0.0,
        "autoresearch_series_average_memory_gb" => 0.0,
        "autoresearch_branch_count" => 0,
        "autoresearch_active_branch_count" => 0,
        "autoresearch_plateau_branch_count" => 0,
        "autoresearch_total_run_count_all_branches" => 0,
        "autoresearch_best_branch" => "",
        "autoresearch_aggregate_keep_rate" => 0.0,
        "autoresearch_aggregate_crash_rate" => 0.0
      }
    else
      assumptions = assumptions_for_claim(state, claim_id)
      evidence = evidence_for_claim(state, claim_id)
      attacks = attacks_for_claim(state, claim_id)
      artifacts = artifacts_for_claim(state, claim_id)
      inputs = inputs_for_claim(state, claim_id)
      hypotheses = hypotheses_for_claim(state, claim_id)
      protocols = protocols_for_claim(state, claim_id)
      targets = targets_for_claim(state, claim_id)
      eval_suites = eval_suites_for_claim(state, claim_id)
      mutation_candidates = mutation_candidates_for_claim(state, claim_id)
      eval_runs = eval_runs_for_claim(state, claim_id)
      decisions = decisions_for_claim(state, claim_id)
      executions = executions_for_claim(state, claim_id)

      autoresearch_meta = Map.get(claim.metadata, "autoresearch", %{})
      autoresearch_series = Map.get(autoresearch_meta, "series", %{})
      autoresearch_aggregate = Map.get(autoresearch_meta, "aggregate_series", %{})

      support_score =
        evidence
        |> Enum.filter(&(&1.direction == :support))
        |> Enum.map(&(&1.strength * &1.confidence))
        |> Enum.sum()

      contradict_score =
        evidence
        |> Enum.filter(&(&1.direction == :contradict))
        |> Enum.map(&(&1.strength * &1.confidence))
        |> Enum.sum()

      inconclusive_score =
        evidence
        |> Enum.filter(&(&1.direction == :inconclusive))
        |> Enum.map(&(&1.strength * &1.confidence))
        |> Enum.sum()

      evidence_weight = support_score + contradict_score + inconclusive_score

      {belief, uncertainty} =
        if evidence_weight == 0 do
          {0.0, 1.0}
        else
          belief = Models.clamp((support_score + 0.5 * inconclusive_score) / evidence_weight)
          uncertainty = Models.clamp(1.0 - abs(support_score - contradict_score) / evidence_weight)
          {belief, uncertainty}
        end

      open_attacks = Enum.filter(attacks, &(&1.status == :open))
      open_attack_load = Models.clamp(Enum.sum(Enum.map(open_attacks, & &1.severity)) / 2.0)

      average_assumption_risk =
        if length(assumptions) > 0 do
          Enum.sum(Enum.map(assumptions, & &1.risk)) / length(assumptions)
        else
          0.0
        end

      highest_risk_assumption = Enum.max_by(assumptions, & &1.risk, fn -> nil end)

      method_artifact_count = Enum.count(artifacts, &(&1.kind == :method))
      paper_artifact_count = Enum.count(artifacts, &(&1.kind == :paper))

      # Candidate scoring
      candidate_scores =
        eval_runs
        |> Enum.group_by(& &1.candidate_id)
        |> Enum.map(fn {cid, runs} ->
          {cid, Enum.map(runs, & &1.score)}
        end)
        |> Map.new()

      candidate_passes =
        eval_runs
        |> Enum.group_by(& &1.candidate_id)
        |> Enum.map(fn {cid, runs} ->
          {cid, Enum.map(runs, & &1.passed)}
        end)
        |> Map.new()

      {best_candidate_id, best_candidate_score, candidate_average_pass_rate, evaluated_candidates} =
        Enum.reduce(mutation_candidates, {"", 0.0, 0.0, []}, fn candidate, acc ->
          scores = Map.get(candidate_scores, candidate.id, [])
          passes = Map.get(candidate_passes, candidate.id, [])

          if length(scores) > 0 do
            average_score = Enum.sum(scores) / length(scores)
            pass_rate =
              if length(passes) > 0 do
                Enum.count(passes, & &1) / length(passes)
              else
                0.0
              end

            {current_best_id, current_best_score, current_avg_pass, current_evaluated} = acc

            if average_score > current_best_score do
              {candidate.id, average_score, current_avg_pass + pass_rate,
               [{candidate, average_score} | current_evaluated]}
            else
              {current_best_id, current_best_score, current_avg_pass + pass_rate,
               [{candidate, average_score} | current_evaluated]}
            end
          else
            acc
          end
        end)

      candidate_average_pass_rate =
        if length(evaluated_candidates) > 0 do
          candidate_average_pass_rate / length(evaluated_candidates)
        else
          0.0
        end

      # Stagnation calculation
      sorted_by_creation =
        Enum.sort_by(evaluated_candidates, fn {cand, _score} -> cand.created_at end)

      {_, stagnation_candidate_count} =
        Enum.reduce(sorted_by_creation, {-1.0, 0}, fn {_cand, avg_score},
                                                         {running_best, stagnation_count} ->
          if avg_score > running_best + 1.0e-9 do
            {avg_score, 0}
          else
            {running_best, stagnation_count + 1}
          end
        end)

      threshold_met = Enum.any?(eval_suites, fn suite -> best_candidate_score >= suite.pass_threshold end)

      promoted_candidate_count = Enum.count(targets, &(&1.promoted_candidate_id != "" and not is_nil(&1.promoted_candidate_id)))

      # Execution metrics
      total_runtime_seconds = Enum.sum(Enum.map(executions, &(&1.runtime_seconds || 0.0)))
      failed_runtime_seconds =
        executions
        |> Enum.filter(&(&1.status == :failed))
        |> Enum.map(&(&1.runtime_seconds || 0.0))
        |> Enum.sum()

      total_cost_usd = Enum.sum(Enum.map(executions, &(&1.cost_estimate_usd || 0.0)))
      failed_cost_usd =
        executions
        |> Enum.filter(&(&1.status == :failed))
        |> Enum.map(&(&1.cost_estimate_usd || 0.0))
        |> Enum.sum()

      known_artifact_qualities =
        Enum.filter(executions, &(not is_nil(&1.artifact_quality)))
        |> Enum.map(& &1.artifact_quality)

      average_artifact_quality =
        if length(known_artifact_qualities) > 0 do
          Enum.sum(known_artifact_qualities) / length(known_artifact_qualities)
        else
          0.0
        end

      %{
        "belief" => safe_round(belief, 6),
        "uncertainty" => safe_round(uncertainty, 6),
        "support_score" => safe_round(support_score, 6),
        "contradict_score" => safe_round(contradict_score, 6),
        "inconclusive_score" => safe_round(inconclusive_score, 6),
        "evidence_weight" => safe_round(evidence_weight, 6),
        "evidence_count" => length(evidence),
        "open_attack_count" => length(open_attacks),
        "open_attack_load" => safe_round(open_attack_load, 6),
        "artifact_count" => length(artifacts),
        "input_count" => length(inputs),
        "hypothesis_count" => length(hypotheses),
        "protocol_count" => length(protocols),
        "ready_protocol_count" =>
          Enum.count(protocols, &(&1.status in [:ready, :materialized])),
        "method_artifact_count" => method_artifact_count,
        "paper_artifact_count" => paper_artifact_count,
        "target_count" => length(targets),
        "eval_suite_count" => length(eval_suites),
        "mutation_candidate_count" => length(mutation_candidates),
        "eval_run_count" => length(eval_runs),
        "reviewed_candidate_count" =>
          Enum.count(mutation_candidates, &(&1.review_status in [:approved, :rejected])),
        "approved_candidate_count" =>
          Enum.count(mutation_candidates, &(&1.review_status == :approved)),
        "promoted_candidate_count" => promoted_candidate_count,
        "optimization_best_candidate_id" => best_candidate_id,
        "optimization_best_score" => safe_round(best_candidate_score, 6),
        "optimization_average_pass_rate" => safe_round(candidate_average_pass_rate, 6),
        "optimization_threshold_met" => threshold_met,
        "optimization_stagnation_candidate_count" => stagnation_candidate_count,
        "assumption_risk" => safe_round(average_assumption_risk, 6),
        "decision_count" => length(decisions),
        "execution_count" => length(executions),
        "failed_execution_count" => Enum.count(executions, &(&1.status == :failed)),
        "successful_execution_count" => Enum.count(executions, &(&1.status == :succeeded)),
        "total_runtime_seconds" => safe_round(total_runtime_seconds, 3),
        "failed_runtime_seconds" => safe_round(failed_runtime_seconds, 3),
        "total_cost_usd" => safe_round(total_cost_usd, 6),
        "failed_cost_usd" => safe_round(failed_cost_usd, 6),
        "average_artifact_quality" => safe_round(average_artifact_quality, 6),
        "highest_risk_assumption_id" =>
          (if highest_risk_assumption, do: highest_risk_assumption.id, else: ""),
        "highest_risk_assumption_risk" =>
          safe_round((if highest_risk_assumption, do: highest_risk_assumption.risk, else: 0.0), 6),
        "autoresearch_series_run_count" => Map.get(autoresearch_series, "total_runs", 0),
        "autoresearch_series_keep_rate" =>
          safe_round(Map.get(autoresearch_series, "keep_rate", 0.0), 6),
        "autoresearch_series_crash_rate" =>
          safe_round(Map.get(autoresearch_series, "crash_rate", 0.0), 6),
        "autoresearch_series_frontier_improvement_count" =>
          Map.get(autoresearch_series, "frontier_improvement_count", 0),
        "autoresearch_series_stagnation_run_count" =>
          Map.get(autoresearch_series, "stagnation_run_count", 0),
        "autoresearch_series_best_improvement_bpb" =>
          safe_round(Map.get(autoresearch_series, "best_improvement_bpb", 0.0), 6),
        "autoresearch_series_average_memory_gb" =>
          safe_round(Map.get(autoresearch_series, "average_memory_gb", 0.0), 3),
        "autoresearch_branch_count" => Map.get(autoresearch_aggregate, "branch_count", 0),
        "autoresearch_active_branch_count" =>
          Map.get(autoresearch_aggregate, "active_branch_count", 0),
        "autoresearch_plateau_branch_count" =>
          Map.get(autoresearch_aggregate, "plateau_branch_count", 0),
        "autoresearch_total_run_count_all_branches" =>
          Map.get(autoresearch_aggregate, "total_runs", 0),
        "autoresearch_best_branch" => Map.get(autoresearch_aggregate, "preferred_branch", "") |> String.trim(),
        "autoresearch_aggregate_keep_rate" =>
          safe_round(Map.get(autoresearch_aggregate, "keep_rate", 0.0), 6),
        "autoresearch_aggregate_crash_rate" =>
          safe_round(Map.get(autoresearch_aggregate, "crash_rate", 0.0), 6)
      }
    end
  end

  defp derive_status(_claim, metrics) do
    contradict_score = Map.get(metrics, "contradict_score", 0.0)
    support_score = Map.get(metrics, "support_score", 0.0)
    open_attack_load = Map.get(metrics, "open_attack_load", 0.0)
    evidence_count = Map.get(metrics, "evidence_count", 0)
    open_attack_count = Map.get(metrics, "open_attack_count", 0)

    cond do
      contradict_score >= max(0.7, support_score * 1.25) ->
        :falsified

      support_score >= max(0.7, contradict_score * 1.5) and open_attack_load < 0.25 ->
        :supported

      evidence_count > 0 or open_attack_count > 0 ->
        if contradict_score > 0 or open_attack_count > 0 do
          :contested
        else
          :active
        end

      true ->
        :proposed
    end
  end

  # Helper functions for fetching entities
  defp fetch_claim(state, claim_id) do
    case Map.get(state.claims, claim_id) do
      nil -> {:error, :not_found}
      claim -> {:ok, claim}
    end
  end

  defp fetch_input(state, input_id) do
    case Map.get(state.inputs, input_id) do
      nil -> {:error, :not_found}
      input -> {:ok, input}
    end
  end

  defp fetch_hypothesis(state, hypothesis_id) do
    case Map.get(state.hypotheses, hypothesis_id) do
      nil -> {:error, :not_found}
      hypothesis -> {:ok, hypothesis}
    end
  end

  defp fetch_protocol(state, protocol_id) do
    case Map.get(state.protocols, protocol_id) do
      nil -> {:error, :not_found}
      protocol -> {:ok, protocol}
    end
  end

  defp fetch_decision(state, decision_id) do
    case Map.get(state.decisions, decision_id) do
      nil -> {:error, :not_found}
      decision -> {:ok, decision}
    end
  end

  defp fetch_target(state, target_id) do
    case Map.get(state.targets, target_id) do
      nil -> {:error, :not_found}
      target -> {:ok, target}
    end
  end

  defp fetch_eval_suite(state, suite_id) do
    case Map.get(state.eval_suites, suite_id) do
      nil -> {:error, :not_found}
      suite -> {:ok, suite}
    end
  end

  defp fetch_mutation_candidate(state, candidate_id) do
    case Map.get(state.mutation_candidates, candidate_id) do
      nil -> {:error, :not_found}
      candidate -> {:ok, candidate}
    end
  end


  defp assumptions_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.assumption_ids
        |> Enum.map(&Map.get(state.assumptions, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp evidence_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.evidence_ids
        |> Enum.map(&Map.get(state.evidence, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp attacks_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.attack_ids
        |> Enum.map(&Map.get(state.attacks, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp artifacts_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.artifact_ids
        |> Enum.map(&Map.get(state.artifacts, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp inputs_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.input_ids
        |> Enum.map(&Map.get(state.inputs, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp hypotheses_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.hypothesis_ids
        |> Enum.map(&Map.get(state.hypotheses, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp protocols_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.protocol_ids
        |> Enum.map(&Map.get(state.protocols, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp targets_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.target_ids
        |> Enum.map(&Map.get(state.targets, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp eval_suites_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.eval_suite_ids
        |> Enum.map(&Map.get(state.eval_suites, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp mutation_candidates_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.mutation_candidate_ids
        |> Enum.map(&Map.get(state.mutation_candidates, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp eval_runs_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.eval_run_ids
        |> Enum.map(&Map.get(state.eval_runs, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp decisions_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.decision_ids
        |> Enum.map(&Map.get(state.decisions, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp executions_for_claim(state, claim_id) do
    case fetch_claim(state, claim_id) do
      {:ok, claim} ->
        claim.execution_ids
        |> Enum.map(&Map.get(state.executions, &1))
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end
  defp maybe_default("", default), do: default
  defp maybe_default(nil, default), do: default
  defp maybe_default(value, _default), do: value
end
