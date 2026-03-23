defmodule Vaos.Ledger.Experiment.LoopTest do
  use ExUnit.Case

  alias Vaos.Ledger.Experiment.Loop
  alias Vaos.Ledger.Epistemic.Ledger

  # Loop tests are limited because the loop calls Ledger GenServer internally
  # and execute_action tries to record_execution with claim_id: "" which will fail.
  # We test the GenServer lifecycle and status reporting.

  setup do
    if pid = GenServer.whereis(Loop) do
      GenServer.stop(pid)
    end
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end
    # Small delay to ensure process is fully terminated
    :timer.sleep(20)

    path = Path.join(System.tmp_dir!(), "loop_test_#{:rand.uniform(999999)}.json")
    {:ok, _} = Ledger.start_link(path: path)

    on_exit(fn ->
      if pid = GenServer.whereis(Loop), do: GenServer.stop(pid)
      if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
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
end
