defmodule Vaos.Ledger.ML.RunnerTest do
  use ExUnit.Case

  alias Vaos.Ledger.ML.Runner

  # A simple experiment_fn that returns decreasing loss
  defp make_experiment_fn(opts \\ []) do
    fail_at = Keyword.get(opts, :fail_at)
    delay_ms = Keyword.get(opts, :delay_ms, 0)

    fn config ->
      step = Map.get(config, :step, 0)

      if fail_at && step >= fail_at do
        {:error, "intentional failure at step #{step}"}
      else
        if delay_ms > 0, do: Process.sleep(delay_ms)
        loss = max(0.01, 1.0 - step * 0.01)
        {:ok, %{metrics: %{loss: loss, accuracy: 1.0 - loss}}}
      end
    end
  end

  describe "start_link and run" do
    test "runs experiment to completion with step budget" do
      experiment_fn = make_experiment_fn()

      {:ok, pid} = Runner.start_link(
        trial_id: "test_run_1",
        experiment_fn: experiment_fn,
        max_steps: 10,
        max_seconds: 60,
        checkpoint_interval: 5
      )

      :ok = Runner.run(pid)

      # Wait for completion
      :timer.sleep(200)

      {:ok, status} = Runner.get_status(pid)
      assert status.status == :completed
      assert status.current_step == 10
      assert status.best_metrics != nil
      assert status.best_metrics.loss <= 1.0

      GenServer.stop(pid)
    end

    test "rejects double run" do
      experiment_fn = make_experiment_fn(delay_ms: 50)

      {:ok, pid} = Runner.start_link(
        trial_id: "test_double",
        experiment_fn: experiment_fn,
        max_steps: 100,
        max_seconds: 60
      )

      :ok = Runner.run(pid)
      assert {:error, :already_running} = Runner.run(pid)

      GenServer.stop(pid)
    end
  end

  describe "step tracking" do
    test "tracks metrics history" do
      experiment_fn = make_experiment_fn()

      {:ok, pid} = Runner.start_link(
        trial_id: "test_metrics",
        experiment_fn: experiment_fn,
        max_steps: 5,
        max_seconds: 60,
        checkpoint_interval: 2
      )

      :ok = Runner.run(pid)
      :timer.sleep(200)

      {:ok, status} = Runner.get_status(pid)
      assert status.current_step == 5
      assert status.metrics_history_length == 5

      GenServer.stop(pid)
    end
  end

  describe "budget enforcement" do
    test "stops after max_steps" do
      experiment_fn = make_experiment_fn()

      {:ok, pid} = Runner.start_link(
        trial_id: "test_step_budget",
        experiment_fn: experiment_fn,
        max_steps: 7,
        max_seconds: 60
      )

      :ok = Runner.run(pid)
      :timer.sleep(200)

      {:ok, status} = Runner.get_status(pid)
      assert status.status == :completed
      assert status.current_step == 7

      GenServer.stop(pid)
    end

    test "stops after time budget" do
      # Each step takes 50ms, budget is 0 seconds (immediately exceeded on next check)
      experiment_fn = make_experiment_fn(delay_ms: 50)

      {:ok, pid} = Runner.start_link(
        trial_id: "test_time_budget",
        experiment_fn: experiment_fn,
        max_steps: 10000,
        max_seconds: 0  # immediate timeout
      )

      :ok = Runner.run(pid)
      # Wait for the time check to fire (1s interval + some buffer)
      :timer.sleep(1500)

      {:ok, status} = Runner.get_status(pid)
      assert status.status in [:time_exceeded, :completed]

      GenServer.stop(pid)
    end
  end

  describe "crash handling" do
    test "handles experiment function error" do
      experiment_fn = make_experiment_fn(fail_at: 3)

      {:ok, pid} = Runner.start_link(
        trial_id: "test_crash",
        experiment_fn: experiment_fn,
        max_steps: 10,
        max_seconds: 60
      )

      :ok = Runner.run(pid)
      :timer.sleep(200)

      {:ok, status} = Runner.get_status(pid)
      assert status.status == :crashed
      assert status.current_step == 3

      GenServer.stop(pid)
    end
  end

  describe "checkpoint and resume" do
    test "saves checkpoint at interval" do
      experiment_fn = make_experiment_fn()

      {:ok, pid} = Runner.start_link(
        trial_id: "test_checkpoint",
        experiment_fn: experiment_fn,
        max_steps: 15,
        max_seconds: 60,
        checkpoint_interval: 5
      )

      :ok = Runner.run(pid)
      :timer.sleep(300)

      {:ok, checkpoint} = Runner.get_checkpoint(pid)
      assert checkpoint != nil
      assert checkpoint.current_step in [5, 10, 15]
      assert is_list(checkpoint.metrics_history)

      GenServer.stop(pid)
    end

    test "resumes from checkpoint" do
      experiment_fn = make_experiment_fn()

      checkpoint = %{
        current_step: 5,
        metrics_history: [%{step: 5, metrics: %{loss: 0.5}}],
        best_metrics: %{loss: 0.5},
        config: %{},
        trial_id: "test_resume"
      }

      {:ok, pid} = Runner.start_link(
        trial_id: "test_resume",
        experiment_fn: experiment_fn,
        max_steps: 10,
        max_seconds: 60,
        checkpoint_interval: 3
      )

      :ok = Runner.resume(pid, checkpoint)
      :timer.sleep(300)

      {:ok, status} = Runner.get_status(pid)
      assert status.status == :completed
      assert status.current_step == 10

      GenServer.stop(pid)
    end
  end

  describe "referee integration" do
    test "sends progress to referee pid" do
      referee = self()
      experiment_fn = make_experiment_fn()

      {:ok, pid} = Runner.start_link(
        trial_id: "test_referee",
        experiment_fn: experiment_fn,
        max_steps: 3,
        max_seconds: 60,
        referee_pid: referee
      )

      :ok = Runner.run(pid)
      :timer.sleep(200)

      # Should have received trial_started
      assert_received {:trial_started, %{version_id: "test_referee"}}

      # Should have received step updates
      assert_received {:step, "test_referee", 1, %{loss: _}}

      # Should have received completion
      assert_received {:trial_completed, %{version_id: "test_referee"}}

      GenServer.stop(pid)
    end

    test "sends crash to referee on failure" do
      referee = self()
      experiment_fn = make_experiment_fn(fail_at: 1)

      {:ok, pid} = Runner.start_link(
        trial_id: "test_crash_notify",
        experiment_fn: experiment_fn,
        max_steps: 10,
        max_seconds: 60,
        referee_pid: referee
      )

      :ok = Runner.run(pid)
      :timer.sleep(200)

      assert_received {:trial_started, %{version_id: "test_crash_notify"}}
      assert_received {:trial_crashed, %{version_id: "test_crash_notify", error: _}}

      GenServer.stop(pid)
    end
  end

  describe "stop_experiment/1" do
    test "stops a running experiment" do
      experiment_fn = make_experiment_fn(delay_ms: 50)

      {:ok, pid} = Runner.start_link(
        trial_id: "test_stop",
        experiment_fn: experiment_fn,
        max_steps: 10000,
        max_seconds: 60
      )

      :ok = Runner.run(pid)
      :timer.sleep(100)
      :ok = Runner.stop_experiment(pid)

      {:ok, status} = Runner.get_status(pid)
      assert status.status == :stopped

      GenServer.stop(pid)
    end
  end
end
