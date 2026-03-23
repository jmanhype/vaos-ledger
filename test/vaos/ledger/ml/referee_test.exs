defmodule Vaos.Ledger.ML.RefereeTest do
  use ExUnit.Case

  alias Vaos.Ledger.ML.Referee

  setup do
    if pid = GenServer.whereis(Referee) do
      GenServer.stop(pid)
    end

    {:ok, _pid} = Referee.start_link(step_budget: 100)
    on_exit(fn ->
      try do
        if pid = GenServer.whereis(Referee), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
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

  describe "handle_call catch-all" do
    test "unknown call returns {:error, :unknown_call} without crashing" do
      result = GenServer.call(Referee, :totally_unknown)
      assert result == {:error, :unknown_call}
      assert Process.alive?(Process.whereis(Referee))
    end
  end

  describe "handle_info catch-all" do
    test "unexpected message does not crash the process" do
      send(Referee, :unexpected_message)
      :timer.sleep(20)
      {:ok, status} = Referee.get_status()
      # Process is still alive and healthy
      assert status.trial_count == 0
    end
  end

  describe "handle_info trial events" do
    test "trial_started adds a trial" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
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
      assert trial.best_score == 0.5
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
      assert trial.current_step == 0
    end

    test "kill logic fires when worst trial is >20% below best" do
      # Restart with high patience so early stop does not interfere
      GenServer.stop(Referee)
      {:ok, _} = Referee.start_link(step_budget: 100, early_stop_patience: 100)

      # Two trials. v1 gets good scores, v2 gets bad scores.
      send(Referee, {:trial_started, %{version_id: "v1"}})
      send(Referee, {:trial_started, %{version_id: "v2"}})
      :timer.sleep(10)

      # step_budget = 100, checkpoint = 50
      # Send 50 steps to each so kill_worst fires
      for step <- 1..50 do
        send(Referee, {:step, %{version_id: "v1", step: step, loss: 0.1}})   # best_score ~0.9
        send(Referee, {:step, %{version_id: "v2", step: step, loss: 0.9}})   # best_score ~0.1
      end
      Process.sleep(100)

      {:ok, status} = Referee.get_status()
      # v2 should have been killed: 0.1 < 0.9 * 0.8 = 0.72
      assert status.killed_count == 1
    end
  end

  describe "get_leaderboard/0" do
    test "returns empty leaderboard initially" do
      {:ok, leaderboard} = Referee.get_leaderboard()
      assert leaderboard == []
    end

    test "returns trials sorted by best score descending" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      send(Referee, {:trial_started, %{version_id: "v2"}})
      send(Referee, {:trial_started, %{version_id: "v3"}})
      :timer.sleep(10)

      # v1: loss 0.3 -> score 0.7
      send(Referee, {:step, %{version_id: "v1", step: 1, loss: 0.3}})
      # v2: loss 0.1 -> score 0.9 (best)
      send(Referee, {:step, %{version_id: "v2", step: 1, loss: 0.1}})
      # v3: loss 0.5 -> score 0.5 (worst)
      send(Referee, {:step, %{version_id: "v3", step: 1, loss: 0.5}})
      :timer.sleep(20)

      {:ok, leaderboard} = Referee.get_leaderboard()
      assert length(leaderboard) == 3
      [first, second, third] = leaderboard
      assert first.version_id == "v2"
      assert second.version_id == "v1"
      assert third.version_id == "v3"
    end
  end

  describe "migrate_trial/2" do
    test "returns trial data for migration" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:step, %{version_id: "v1", step: 1, loss: 0.2}})
      :timer.sleep(10)

      {:ok, migration_data} = Referee.migrate_trial("v1", self())
      assert migration_data.version_id == "v1"
      assert migration_data.best_score == 0.8
      assert migration_data.migrated_to == self()
    end

    test "returns error for unknown trial" do
      assert {:error, :not_found} = Referee.migrate_trial("nonexistent", self())
    end

    test "marks original trial as migrated" do
      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)
      send(Referee, {:step, %{version_id: "v1", step: 1, loss: 0.3}})
      :timer.sleep(10)

      {:ok, _} = Referee.migrate_trial("v1", self())

      {:ok, stats} = Referee.get_trial_stats()
      trial = Enum.find(stats, &(&1.version_id == "v1"))
      assert trial.status == :migrated
    end
  end

  describe "early stop detection" do
    test "kills trial after patience exhausted" do
      # Restart with tight early stop settings
      GenServer.stop(Referee)
      {:ok, _} = Referee.start_link(
        step_budget: 100,
        early_stop_patience: 5,
        early_stop_threshold: 0.01
      )

      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)

      # Send steps with no improvement (same loss)
      for step <- 1..10 do
        send(Referee, {:step, %{version_id: "v1", step: step, loss: 0.5}})
      end
      Process.sleep(100)

      {:ok, status} = Referee.get_status()
      # Trial should be killed due to early stopping
      assert status.killed_count == 1
    end

    test "does not early-stop when still improving" do
      GenServer.stop(Referee)
      {:ok, _} = Referee.start_link(
        step_budget: 100,
        early_stop_patience: 5,
        early_stop_threshold: 0.001
      )

      send(Referee, {:trial_started, %{version_id: "v1"}})
      :timer.sleep(10)

      # Send steps with steady improvement
      for step <- 1..10 do
        loss = 1.0 - step * 0.05
        send(Referee, {:step, %{version_id: "v1", step: step, loss: loss}})
      end
      :timer.sleep(50)

      {:ok, status} = Referee.get_status()
      assert status.killed_count == 0
    end
  end

  describe "crash learner integration" do
    test "forwards crashes to crash learner" do
      # Start a CrashLearner
      {:ok, cl_pid} = Vaos.Ledger.ML.CrashLearner.start_link(
        name: :"cl_referee_test_#{System.unique_integer([:positive])}"
      )

      # Restart referee with crash learner
      GenServer.stop(Referee)
      {:ok, _} = Referee.start_link(step_budget: 100, crash_learner_pid: cl_pid)

      # Send a crash event
      send(Referee, {:trial_crashed, %{version_id: "v1", error: "bad math", step: 5}})
      :timer.sleep(30)

      {:ok, crashes} = Vaos.Ledger.ML.CrashLearner.get_crashes(cl_pid)
      assert length(crashes) == 1
      assert hd(crashes).trial_id == "v1"

      GenServer.stop(cl_pid)
    end

    test "handles missing crash learner gracefully" do
      # Default setup has no crash_learner_pid
      send(Referee, {:trial_crashed, %{version_id: "v1", error: "some error", step: 0}})
      :timer.sleep(20)

      # Referee should still be alive
      {:ok, status} = Referee.get_status()
      assert status.trial_count == 0
    end
  end
end
