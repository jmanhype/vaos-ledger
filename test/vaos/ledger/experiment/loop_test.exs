defmodule Vaos.Ledger.Experiment.LoopTest do
  use ExUnit.Case

  alias Vaos.Ledger.Experiment.Loop
  alias Vaos.Ledger.Epistemic.Ledger

  setup do
    try do
      if pid = GenServer.whereis(Loop), do: GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
    try do
      if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
    :timer.sleep(20)

    path = Path.join(System.tmp_dir!(), "loop_test_#{:rand.uniform(999999)}.json")
    {:ok, _} = Ledger.start_link(path: path)

    on_exit(fn ->
      try do
        if pid = GenServer.whereis(Loop), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
      try do
        if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
      File.rm(path)
    end)
    %{path: path}
  end

  describe "start_link/1" do
    test "starts the loop GenServer" do
      {:ok, pid} = Loop.start_link(max_iterations: 5)
      assert Process.alive?(pid)
    end
  end

  describe "get_status/0" do
    test "returns initial status" do
      {:ok, _} = Loop.start_link(max_iterations: 10)
      {:ok, status} = Loop.get_status()
      assert status.iteration == 0
      assert status.best_score == 0.0
      assert status.max_iterations == 10
    end
  end

  describe "handle_call catch-all" do
    test "unknown call returns {:error, :unknown_call} without crashing" do
      {:ok, pid} = Loop.start_link(max_iterations: 5)
      result = GenServer.call(pid, :totally_unknown)
      assert result == {:error, :unknown_call}
      assert Process.alive?(pid)
    end
  end

  describe "handle_info catch-all" do
    test "unexpected message does not crash the process" do
      {:ok, pid} = Loop.start_link(max_iterations: 5)
      send(pid, :unexpected_message)
      :timer.sleep(20)
      assert Process.alive?(pid)
    end
  end

  describe "run/2 with active claims" do
    test "loop iterates and returns final state with best_score set" do
      {:ok, _} = Loop.start_link(max_iterations: 3)

      # Seed a claim so the controller can propose real actions
      claim = Ledger.add_claim(title: "Loop Test Claim", statement: "Automated experiment")
      Ledger.add_assumption(claim_id: claim.id, text: "Assume convergence", risk: 0.6)

      {:ok, final} = Loop.run(Ledger, max_iterations: 3)
      assert final.iteration == 3
      assert is_float(final.best_score)
    end

    test "loop skips execution when no claims exist (bootstrap mode)" do
      {:ok, _} = Loop.start_link(max_iterations: 2)
      # No claims in ledger — controller returns bootstrap proposal with claim_id ""
      {:ok, final} = Loop.run(Ledger, max_iterations: 2)
      # Should still complete all iterations without error
      assert final.iteration == 2
      # best_score stays 0.0 because no executions were scored
      assert final.best_score == 0.0
    end
  end
end
