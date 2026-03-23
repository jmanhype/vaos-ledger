defmodule Vaos.Ledger.ML.RefereeTest do
  use ExUnit.Case

  alias Vaos.Ledger.ML.Referee

  setup do
    if pid = GenServer.whereis(Referee) do
      GenServer.stop(pid)
    end

    {:ok, _pid} = Referee.start_link(step_budget: 100)
    on_exit(fn ->
      if pid = GenServer.whereis(Referee), do: GenServer.stop(pid)
    end)
    :ok
  end

  describe "start_link/1" do
    test "starts with empty trials" do
      {:ok, status} = Referee.get_status()
      assert status.step_budget == 100
      assert status.trial_count == 0
      assert status.killed_count == 0
    end
  end

  describe "get_trial_stats/0" do
    test "returns empty list initially" do
      {:ok, stats} = Referee.get_trial_stats()
      assert stats == []
    end
  end

  describe "handle_info trial events" do
    test "trial_started adds a trial" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      # Give GenServer time to process
      :timer.sleep(10)
      {:ok, status} = Referee.get_status()
      assert status.trial_count == 1
    end

    test "trial_completed removes a trial" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:trial_completed, %{version_id: "v1"}})
      :timer.sleep(10)
      {:ok, status} = Referee.get_status()
      assert status.trial_count == 0
    end

    test "step updates trial data" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:step, %{version_id: "v1", step: 1, loss: 0.5}})
      :timer.sleep(10)
      {:ok, stats} = Referee.get_trial_stats()
      assert length(stats) == 1
      trial = hd(stats)
      assert trial.version_id == "v1"
      assert trial.current_step == 1
    end

    test "trial_killed marks trial as killed" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:trial_killed, %{version_id: "v1"}})
      :timer.sleep(10)
      {:ok, status} = Referee.get_status()
      assert status.killed_count == 1
    end

    test "ignores steps from killed trials" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:trial_killed, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:step, %{version_id: "v1", step: 5, loss: 0.1}})
      :timer.sleep(10)
      {:ok, stats} = Referee.get_trial_stats()
      trial = Enum.find(stats, &(&1.version_id == "v1"))
      # Should still have 0 steps since the step was ignored
      assert trial.current_step == 0
    end
  end
end
