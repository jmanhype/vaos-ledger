defmodule Vaos.Ledger.Epistemic.ControllerTest do
  use ExUnit.Case

  alias Vaos.Ledger.Epistemic.{Controller, Ledger}

  setup do
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end

    path = Path.join(System.tmp_dir!(), "ctrl_test_#{:rand.uniform(999999)}.json")
    {:ok, _pid} = Ledger.start_link(path: path)
    on_exit(fn ->
      if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
      File.rm(path)
    end)
    %{path: path}
  end

  describe "decide/2" do
    test "returns bootstrap decision when no claims exist" do
      decision = Controller.decide(Ledger)
      assert decision.queue_state == "bootstrap"
      assert decision.primary_action.action_type == :propose_hypothesis
    end

    test "returns analysis decision when claims exist but no proposals" do
      Ledger.add_claim(title: "T", statement: "S")
      decision = Controller.decide(Ledger)
      # Should not be bootstrap since claims exist
      assert decision.queue_state != "bootstrap"
      assert decision.primary_action != nil
    end

    test "returns ranked proposals when claims have evidence" do
      claim = Ledger.add_claim(title: "T", statement: "S", novelty: 0.8, falsifiability: 0.7)
      Ledger.add_evidence(
        claim_id: claim.id, summary: "E",
        direction: :support, strength: 0.7, confidence: 0.6
      )
      Ledger.add_assumption(claim_id: claim.id, text: "A", risk: 0.8)

      decision = Controller.decide(Ledger)
      assert decision.primary_action != nil
      assert decision.primary_action.claim_id == claim.id
      assert is_binary(decision.summary)
    end

    test "respects backlog_limit option" do
      claim = Ledger.add_claim(title: "T", statement: "S", novelty: 0.9, falsifiability: 0.9)
      Ledger.add_evidence(
        claim_id: claim.id, summary: "E",
        direction: :support, strength: 0.8, confidence: 0.7
      )
      Ledger.add_assumption(claim_id: claim.id, text: "A", risk: 0.9)
      Ledger.add_attack(claim_id: claim.id, description: "Att", severity: 0.8)

      decision = Controller.decide(Ledger, backlog_limit: 2)
      assert length(decision.backlog) <= 2
    end
  end
end
