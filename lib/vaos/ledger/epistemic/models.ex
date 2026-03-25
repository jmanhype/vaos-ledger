defmodule Vaos.Ledger.Epistemic.Models do
  @moduledoc """
  Shared structs and utilities for the epistemic ledger system.
  """

  require Logger

  @doc "Clamp a float to [0.0, 1.0]."
  def clamp(value) when is_float(value), do: min(1.0, max(0.0, value))
  def clamp(value) when is_integer(value), do: min(1.0, max(0.0, value / 1))
  def clamp(value) do
    Logger.warning("Models.clamp/1 received non-numeric value: #{inspect(value)}, defaulting to 0.0")
    0.0
  end

  @doc "Clamp a value to [min_val, max_val]."
  def clamp(value, min_val, max_val) when is_number(value), do: min(max_val, max(min_val, value * 1.0))
  def clamp(_value, min_val, _max_val), do: min_val * 1.0

  @doc "Return current UTC datetime as ISO8601 string."
  def utc_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @doc "Serialize a struct to a plain map."
  def serialize_struct(%{__struct__: _} = s), do: Map.from_struct(s)
  def serialize_struct(m) when is_map(m), do: m

  @doc "Return true if action_type is in the given list."
  def action_matches?(action_type, list) when is_list(list) do
    action_type in list
  end

  defmodule Claim do
    @moduledoc false
    defstruct [
      :id, :title, :statement, :status, :novelty, :falsifiability, :confidence,
      :created_at, :updated_at,
      tags: [], assumption_ids: [], evidence_ids: [], attack_ids: [],
      artifact_ids: [], decision_ids: [], execution_ids: [], target_ids: [],
      eval_suite_ids: [], mutation_candidate_ids: [], eval_run_ids: [],
      input_ids: [], hypothesis_ids: [], protocol_ids: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "claim_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      defaults = [id: id, created_at: now, updated_at: now, status: :proposed,
                  novelty: 0.5, falsifiability: 0.5, confidence: 0.0]
      merged = Keyword.merge(defaults, attrs)
      clamp = &Vaos.Ledger.Epistemic.Models.clamp/1
      merged = Keyword.update(merged, :novelty, 0.5, clamp)
      merged = Keyword.update(merged, :falsifiability, 0.5, clamp)
      merged = Keyword.update(merged, :confidence, 0.0, clamp)
      struct!(__MODULE__, merged)
    end
  end

  defmodule Assumption do
    @moduledoc false
    defstruct [:id, :claim_id, :text, :rationale, :risk, :created_at, tags: [], metadata: %{}]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "assum_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, risk: 0.5, rationale: ""], attrs))
    end
  end

  defmodule Evidence do
    @moduledoc false
    defstruct [
      :id, :claim_id, :summary, :direction, :strength, :confidence,
      :source_type, :source_ref, :actor_id, :trace_id, :created_at,
      artifact_paths: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "evid_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, direction: :inconclusive,
                                        strength: 0.5, confidence: 0.5], attrs))
    end
  end

  defmodule Attack do
    @moduledoc false
    defstruct [
      :id, :claim_id, :description, :target_kind, :target_id,
      :severity, :status, :created_at, :resolution, :actor_id, :trace_id, metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "atk_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, status: :open], attrs))
    end
  end

  defmodule Artifact do
    @moduledoc false
    defstruct [
      :id, :claim_id, :kind, :title, :content, :source_type, :source_ref,
      :source_path, :created_at, :updated_at, metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "artif_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now, kind: :method], attrs))
    end
  end

  defmodule InputArtifact do
    @moduledoc false
    defstruct [
      :id, :title, :input_type, :content, :source_type, :source_ref,
      :source_path, :summary, :created_at, :updated_at,
      linked_claim_ids: [], tags: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "input_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now], attrs))
    end
  end

  defmodule InnovationHypothesis do
    @moduledoc false
    defstruct [
      :id, :input_id, :title, :statement, :summary, :rationale,
      :recommended_mode, :target_type, :target_title, :target_source_strategy,
      :leverage, :testability, :novelty, :strategic_novelty,
      :domain_differentiation, :fork_specificity, :optimization_readiness,
      :overall_score, :status, :materialized_claim_id, :created_at, :updated_at,
      mutable_fields: [], suggested_constraints: [], eval_outline: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "hyp_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now, status: :proposed], attrs))
    end
  end

  defmodule ProtocolDraft do
    @moduledoc false
    defstruct [
      :id, :input_id, :hypothesis_id, :recommended_mode, :status,
      :extraction_confidence, :eval_confidence, :execution_readiness,
      :materialized_claim_id, :created_at, :updated_at,
      artifact_candidates: [], target_spec: %{}, eval_plan: %{},
      baseline_plan: %{}, blockers: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "proto_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now, status: :draft], attrs))
    end
  end

  defmodule ArtifactTarget do
    @moduledoc false
    defstruct [
      :id, :claim_id, :mode, :target_type, :title, :content, :source_type,
      :source_ref, :source_path, :promoted_candidate_id, :created_at, :updated_at,
      mutable_fields: [], invariant_constraints: %{}, metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "tgt_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now], attrs))
    end
  end

  defmodule EvalSuite do
    @moduledoc false
    defstruct [
      :id, :claim_id, :target_id, :name, :compatible_target_type,
      :scoring_method, :aggregation, :pass_threshold, :repetitions,
      :created_at, :updated_at, cases: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "suite_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now], attrs))
    end
  end

  defmodule MutationCandidate do
    @moduledoc false
    defstruct [
      :id, :claim_id, :target_id, :parent_candidate_id, :summary, :content,
      :source_type, :source_ref, :source_path, :review_status, :review_notes,
      :created_at, :updated_at, artifact_paths: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "cand_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, updated_at: now, review_status: :pending], attrs))
    end
  end

  defmodule EvalRun do
    @moduledoc false
    defstruct [
      :id, :claim_id, :target_id, :suite_id, :candidate_id, :case_id,
      :run_index, :score, :passed, :raw_output, :runtime_seconds,
      :cost_estimate_usd, :created_at, artifact_paths: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "run_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now], attrs))
    end
  end

  defmodule DecisionRecord do
    @moduledoc false
    defstruct [
      :id, :claim_id, :claim_title, :action_type, :executor, :mode, :stage,
      :priority, :expected_information_gain, :reason, :command_hint, :created_at,
      metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "dec_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now], attrs))
    end
  end

  defmodule ExecutionRecord do
    @moduledoc false
    defstruct [
      :id, :decision_id, :claim_id, :claim_title, :action_type, :executor,
      :status, :mode, :notes, :runtime_seconds, :cost_estimate_usd,
      :artifact_quality, :created_at, artifact_paths: [], metadata: %{}
    ]

    def new(attrs) do
      now = Vaos.Ledger.Epistemic.Models.utc_now()
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      id = attrs[:id] || "exec_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      struct!(__MODULE__, Keyword.merge([id: id, created_at: now, status: :running], attrs))
    end
  end

  defmodule ActionProposal do
    @moduledoc false
    defstruct [
      :claim_id, :claim_title, :action_type, :expected_information_gain,
      :priority, :reason, :executor, :mode, :stage, :command_hint
    ]

    def new(attrs) do
      attrs = Keyword.reject(attrs, fn {_k, v} -> is_nil(v) end)
      struct!(__MODULE__, Keyword.merge([executor: :manual, mode: "ml_research"], attrs))
    end
  end

  defmodule ControllerDecision do
    @moduledoc false
    defstruct [:queue_state, :summary, :primary_action, backlog: []]

    def new(attrs) do
      struct!(__MODULE__, attrs)
    end
  end
end
