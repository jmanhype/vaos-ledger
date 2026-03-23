defmodule Vaos.Ledger.Epistemic.LedgerTest do
  use ExUnit.Case

  alias Vaos.Ledger.Epistemic.Ledger

  setup do
    # Stop the application-started ledger to avoid name conflicts
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end

    path = Path.join(System.tmp_dir!(), "ledger_test_#{:rand.uniform(999999)}.json")
    {:ok, _pid} = Ledger.start_link(path: path)
    on_exit(fn ->
      if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
      File.rm(path)
    end)
    %{path: path}
  end

  describe "start_link/1 and init" do
    test "starts with empty state", %{path: _path} do
      state = Ledger.state()
      assert state.claims == %{}
      assert state.assumptions == %{}
      assert state.evidence == %{}
    end

    test "creates the ledger file on first persist" do
      claim = Ledger.add_claim(title: "Test", statement: "Test statement")
      assert claim.title == "Test"
      state = Ledger.state()
      assert File.exists?(state.path)
    end
  end

  describe "add_claim/1" do
    test "adds a claim and persists" do
      claim = Ledger.add_claim(title: "Claim 1", statement: "Statement 1")
      assert claim.title == "Claim 1"
      assert claim.statement == "Statement 1"
      assert String.starts_with?(claim.id, "claim_")
      assert claim.status in [:proposed, :active]

      claims = Ledger.list_claims()
      assert length(claims) == 1
    end

    test "adds claim with custom id" do
      claim = Ledger.add_claim(title: "C", statement: "S", id: "custom_id")
      assert claim.id == "custom_id"
    end

    test "adds claim with tags and metadata" do
      claim = Ledger.add_claim(
        title: "T", statement: "S",
        tags: ["a", "b"], metadata: %{"key" => "val"}
      )
      assert claim.tags == ["a", "b"]
      assert claim.metadata == %{"key" => "val"}
    end
  end

  describe "get_claim/1" do
    test "returns {:ok, claim} for existing claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      assert {:ok, found} = Ledger.get_claim(claim.id)
      assert found.id == claim.id
    end

    test "returns {:error, :not_found} for missing claim" do
      assert {:error, :not_found} = Ledger.get_claim("nonexistent")
    end
  end

  describe "list_claims/0" do
    test "returns empty list when no claims" do
      assert Ledger.list_claims() == []
    end

    test "returns claims sorted by created_at" do
      c1 = Ledger.add_claim(title: "First", statement: "S")
      c2 = Ledger.add_claim(title: "Second", statement: "S")
      claims = Ledger.list_claims()
      assert length(claims) == 2
      assert hd(claims).id == c1.id
      assert List.last(claims).id == c2.id
    end
  end

  describe "add_assumption/1" do
    test "adds assumption to existing claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      assumption = Ledger.add_assumption(claim_id: claim.id, text: "Assume X")
      assert assumption.claim_id == claim.id
      assert assumption.text == "Assume X"
      assert assumption.risk == 0.5
    end

    test "returns error for nonexistent claim" do
      result = Ledger.add_assumption(claim_id: "bad", text: "X")
      assert result == {:error, :not_found}
    end
  end

  describe "add_evidence/1" do
    test "adds evidence to existing claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      evidence = Ledger.add_evidence(
        claim_id: claim.id, summary: "Found evidence",
        direction: :support, strength: 0.9, confidence: 0.8
      )
      assert evidence.direction == :support
      assert evidence.strength == 0.9
    end

    test "returns error for nonexistent claim" do
      result = Ledger.add_evidence(claim_id: "bad", summary: "X")
      assert result == {:error, :not_found}
    end
  end

  describe "add_attack/1" do
    test "adds attack to existing claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      attack = Ledger.add_attack(claim_id: claim.id, description: "Counterargument")
      assert attack.description == "Counterargument"
      assert attack.status == :open
    end
  end

  describe "add_artifact/1" do
    test "adds artifact to existing claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      artifact = Ledger.add_artifact(
        claim_id: claim.id, kind: :method, title: "Method A"
      )
      assert artifact.kind == :method
      assert artifact.title == "Method A"
    end
  end

  describe "register_input/1" do
    test "registers an input artifact" do
      input = Ledger.register_input(
        title: "Paper X", input_type: "paper", content: "content here"
      )
      assert input.title == "Paper X"
      assert input.input_type == "paper"
    end
  end

  describe "add_hypothesis/1" do
    test "adds hypothesis linked to input" do
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(
        input_id: input.id, title: "Hyp 1", statement: "Hypothesis"
      )
      assert hyp.input_id == input.id
      assert hyp.title == "Hyp 1"
    end

    test "returns error for nonexistent input" do
      result = Ledger.add_hypothesis(input_id: "bad", title: "H", statement: "S")
      assert result == {:error, :not_found}
    end
  end

  describe "add_protocol_draft/1" do
    test "adds protocol draft" do
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "S")
      proto = Ledger.add_protocol_draft(
        input_id: input.id, hypothesis_id: hyp.id,
        recommended_mode: "ml_research"
      )
      assert proto.input_id == input.id
      assert proto.hypothesis_id == hyp.id
      assert proto.status == :draft
    end

    test "rejects mismatched input/hypothesis" do
      input1 = Ledger.register_input(title: "I1", input_type: "paper", content: "C")
      input2 = Ledger.register_input(title: "I2", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(input_id: input1.id, title: "H", statement: "S")
      result = Ledger.add_protocol_draft(
        input_id: input2.id, hypothesis_id: hyp.id,
        recommended_mode: "ml_research"
      )
      assert result == {:error, :input_hypothesis_mismatch}
    end
  end

  describe "register_target/1" do
    test "registers target for claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "optimize", target_type: "code", title: "Target"
      )
      assert target.mode == "optimize"
      assert target.target_type == "code"
    end
  end

  describe "register_eval_suite/1" do
    test "registers eval suite for claim and target" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "optimize", target_type: "code", title: "T"
      )
      suite = Ledger.register_eval_suite(
        claim_id: claim.id, target_id: target.id,
        name: "Suite1", compatible_target_type: "code"
      )
      assert suite.name == "Suite1"
    end
  end

  describe "add_mutation_candidate/1" do
    test "adds mutation candidate" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "optimize", target_type: "code", title: "T"
      )
      cand = Ledger.add_mutation_candidate(
        claim_id: claim.id, target_id: target.id,
        summary: "Mutation 1", content: "code here"
      )
      assert cand.summary == "Mutation 1"
      assert cand.review_status == :pending
    end
  end

  describe "record_eval_run/1" do
    test "records eval run" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "optimize", target_type: "code", title: "T"
      )
      suite = Ledger.register_eval_suite(
        claim_id: claim.id, target_id: target.id,
        name: "S", compatible_target_type: "code"
      )
      cand = Ledger.add_mutation_candidate(
        claim_id: claim.id, target_id: target.id,
        summary: "M", content: "C"
      )
      run = Ledger.record_eval_run(
        claim_id: claim.id, target_id: target.id,
        suite_id: suite.id, candidate_id: cand.id,
        case_id: "case_1", run_index: 1, score: 0.85, passed: true
      )
      assert run.score == 0.85
      assert run.passed == true
    end
  end

  describe "promote_candidate/2" do
    test "promotes a candidate to a target" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "optimize", target_type: "code", title: "T"
      )
      cand = Ledger.add_mutation_candidate(
        claim_id: claim.id, target_id: target.id,
        summary: "M", content: "C"
      )
      updated = Ledger.promote_candidate(target.id, cand.id)
      assert updated.promoted_candidate_id == cand.id
    end
  end

  describe "claim_snapshot/1" do
    test "returns full snapshot of claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      Ledger.add_assumption(claim_id: claim.id, text: "A")
      Ledger.add_evidence(claim_id: claim.id, summary: "E", direction: :support, strength: 0.8)

      snapshot = Ledger.claim_snapshot(claim.id)
      assert is_map(snapshot)
      assert snapshot.claim.title == "T"
      assert length(snapshot.assumptions) == 1
      assert length(snapshot.evidence) == 1
    end

    test "returns error for nonexistent claim" do
      assert {:error, :not_found} = Ledger.claim_snapshot("bad")
    end
  end

  describe "summary_rows/0" do
    test "returns summary for all claims" do
      Ledger.add_claim(title: "C1", statement: "S1")
      Ledger.add_claim(title: "C2", statement: "S2")
      rows = Ledger.summary_rows()
      assert length(rows) == 2
      assert Enum.all?(rows, &is_map/1)
      assert Enum.all?(rows, &Map.has_key?(&1, :confidence))
    end
  end

  describe "record_decision/2 and record_execution/1" do
    test "records decision and execution" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      proposal = %Vaos.Ledger.Epistemic.Models.ActionProposal{
        claim_id: claim.id, claim_title: "T",
        action_type: :run_experiment, expected_information_gain: 0.8,
        priority: "now", reason: "test", executor: :manual,
        mode: "ml_research", stage: "exploration", command_hint: "do it"
      }
      decision = Ledger.record_decision(proposal)
      assert decision.action_type == :run_experiment

      execution = Ledger.record_execution(
        decision_id: decision.id, status: :succeeded,
        notes: "Done", runtime_seconds: 5.0
      )
      assert execution.status == :succeeded
      assert execution.claim_id == claim.id
    end

    test "records execution without decision" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      execution = Ledger.record_execution(
        claim_id: claim.id, action_type: :run_experiment,
        status: :succeeded, notes: "Direct"
      )
      assert execution.status == :succeeded
      assert execution.claim_id == claim.id
    end
  end

  describe "JSON persistence round-trip" do
    test "save and reload preserves data", %{path: path} do
      claim = Ledger.add_claim(title: "Persist Test", statement: "Round trip")
      Ledger.add_evidence(claim_id: claim.id, summary: "E1", direction: :support, strength: 0.7)
      Ledger.add_assumption(claim_id: claim.id, text: "A1")
      Ledger.add_attack(claim_id: claim.id, description: "Attack 1")
      Ledger.save()

      # Stop and restart
      GenServer.stop(Ledger)
      {:ok, _} = Ledger.start_link(path: path)

      claims = Ledger.list_claims()
      assert length(claims) == 1
      assert hd(claims).title == "Persist Test"

      assumptions = Ledger.assumptions_for_claim(claim.id)
      assert length(assumptions) == 1

      evidence = Ledger.evidence_for_claim(claim.id)
      assert length(evidence) == 1

      attacks = Ledger.attacks_for_claim(claim.id)
      assert length(attacks) == 1
    end

    test "round-trips complex state with all entity types", %{path: path} do
      claim = Ledger.add_claim(title: "Full", statement: "S")
      Ledger.add_assumption(claim_id: claim.id, text: "A")
      Ledger.add_evidence(claim_id: claim.id, summary: "E", direction: :support, strength: 0.9)
      Ledger.add_attack(claim_id: claim.id, description: "D")
      Ledger.add_artifact(claim_id: claim.id, kind: :method, title: "M")
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "HS")
      target = Ledger.register_target(
        claim_id: claim.id, mode: "opt", target_type: "code", title: "T"
      )
      suite = Ledger.register_eval_suite(
        claim_id: claim.id, target_id: target.id,
        name: "S", compatible_target_type: "code"
      )
      cand = Ledger.add_mutation_candidate(
        claim_id: claim.id, target_id: target.id,
        summary: "M", content: "C"
      )
      Ledger.record_eval_run(
        claim_id: claim.id, target_id: target.id,
        suite_id: suite.id, candidate_id: cand.id,
        case_id: "c1", run_index: 1, score: 0.9, passed: true
      )

      Ledger.save()
      GenServer.stop(Ledger)
      {:ok, _} = Ledger.start_link(path: path)

      state = Ledger.state()
      assert map_size(state.claims) == 1
      assert map_size(state.assumptions) == 1
      assert map_size(state.evidence) == 1
      assert map_size(state.attacks) == 1
      assert map_size(state.artifacts) == 1
      assert map_size(state.inputs) == 1
      assert map_size(state.hypotheses) == 1
      assert map_size(state.targets) == 1
      assert map_size(state.eval_suites) == 1
      assert map_size(state.mutation_candidates) == 1
      assert map_size(state.eval_runs) == 1
    end
  end

  describe "claim_metrics/1" do
    test "computes metrics for claim with evidence" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      Ledger.add_evidence(claim_id: claim.id, summary: "E1", direction: :support, strength: 0.8, confidence: 0.9)
      Ledger.add_evidence(claim_id: claim.id, summary: "E2", direction: :contradict, strength: 0.3, confidence: 0.5)

      metrics = Ledger.claim_metrics(claim.id)
      assert metrics["evidence_count"] == 2
      assert metrics["support_score"] > 0
      assert metrics["contradict_score"] > 0
      assert metrics["belief"] >= 0.0
      assert metrics["uncertainty"] >= 0.0
    end

    test "returns defaults for nonexistent claim" do
      metrics = Ledger.claim_metrics("nonexistent")
      assert metrics["belief"] == 0.0
      assert metrics["uncertainty"] == 1.0
    end
  end

  describe "refresh_all/0" do
    test "refreshes all claims without error" do
      Ledger.add_claim(title: "T1", statement: "S1")
      Ledger.add_claim(title: "T2", statement: "S2")
      assert :ok = Ledger.refresh_all()
    end
  end

  describe "link operations" do
    test "link_hypothesis_to_claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "HS")
      updated = Ledger.link_hypothesis_to_claim(hyp.id, claim.id, :materialized)
      assert updated.materialized_claim_id == claim.id
      assert updated.status == :materialized
    end

    test "link_input_to_claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      updated = Ledger.link_input_to_claim(input.id, claim.id)
      assert claim.id in updated.linked_claim_ids
    end

    test "link_protocol_to_claim" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "HS")
      proto = Ledger.add_protocol_draft(input_id: input.id, hypothesis_id: hyp.id)
      updated = Ledger.link_protocol_to_claim(proto.id, claim.id, :materialized)
      assert updated.materialized_claim_id == claim.id
    end
  end

  describe "upsert_artifact/1" do
    test "inserts new artifact when none exists" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      artifact = Ledger.upsert_artifact(
        claim_id: claim.id, kind: :method, title: "M1",
        content: "content", source_path: "/a/b"
      )
      assert artifact.title == "M1"
    end

    test "updates existing artifact with same kind and source_path" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      Ledger.upsert_artifact(
        claim_id: claim.id, kind: :method, title: "M1",
        content: "v1", source_path: "/a/b"
      )
      updated = Ledger.upsert_artifact(
        claim_id: claim.id, kind: :method, title: "M1 Updated",
        content: "v2", source_path: "/a/b"
      )
      assert updated.title == "M1 Updated"
      assert updated.content == "v2"

      # Should still be only 1 artifact
      artifacts = Ledger.artifacts_for_claim(claim.id)
      assert length(artifacts) == 1
    end
  end

  describe "list operations" do
    test "list_decisions returns all decisions" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      proposal = %Vaos.Ledger.Epistemic.Models.ActionProposal{
        claim_id: claim.id, claim_title: "T",
        action_type: :run_experiment, expected_information_gain: 0.5,
        priority: "now", reason: "r", executor: :manual,
        mode: "m", stage: "s", command_hint: "c"
      }
      Ledger.record_decision(proposal)
      assert length(Ledger.list_decisions()) == 1
    end

    test "list_executions returns all executions" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      Ledger.record_execution(
        claim_id: claim.id, action_type: :run_experiment,
        status: :succeeded
      )
      assert length(Ledger.list_executions()) == 1
    end

    test "list_inputs returns all inputs" do
      Ledger.register_input(title: "I", input_type: "paper", content: "C")
      assert length(Ledger.list_inputs()) == 1
    end

    test "list_hypotheses returns all hypotheses" do
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "S")
      assert length(Ledger.list_hypotheses()) == 1
    end

    test "list_protocols returns all protocols" do
      input = Ledger.register_input(title: "I", input_type: "paper", content: "C")
      hyp = Ledger.add_hypothesis(input_id: input.id, title: "H", statement: "S")
      Ledger.add_protocol_draft(input_id: input.id, hypothesis_id: hyp.id)
      assert length(Ledger.list_protocols()) == 1
    end
  end
end
