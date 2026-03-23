defmodule Vaos.Ledger.ML.CrashLearnerTest do
  use ExUnit.Case

  alias Vaos.Ledger.ML.CrashLearner

  setup do
    name = :"crash_learner_#{System.unique_integer([:positive])}"
    {:ok, pid} = CrashLearner.start_link(name: name, distill_threshold: 3)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end)

    %{pid: pid}
  end

  describe "start_link/1" do
    test "starts with empty crashes and pitfalls", %{pid: pid} do
      {:ok, crashes} = CrashLearner.get_crashes(pid)
      {:ok, pitfalls} = CrashLearner.get_pitfalls(pid)
      assert crashes == []
      assert pitfalls == []
    end
  end

  describe "report_crash/5" do
    test "records a crash", %{pid: pid} do
      CrashLearner.report_crash(pid, "trial_1", "ArithmeticError: bad argument", nil, %{step: 10})
      :timer.sleep(20)
      {:ok, crashes} = CrashLearner.get_crashes(pid)
      assert length(crashes) == 1
      assert hd(crashes).trial_id == "trial_1"
      assert hd(crashes).error == "ArithmeticError: bad argument"
    end

    test "records multiple crashes in order (most recent first)", %{pid: pid} do
      CrashLearner.report_crash(pid, "trial_1", "error_1")
      CrashLearner.report_crash(pid, "trial_2", "error_2")
      CrashLearner.report_crash(pid, "trial_3", "error_3")
      :timer.sleep(30)
      {:ok, crashes} = CrashLearner.get_crashes(pid)
      assert length(crashes) == 3
      assert hd(crashes).trial_id == "trial_3"
    end
  end

  describe "auto-distill pattern detection" do
    test "distills pitfall after threshold (3) similar crashes", %{pid: pid} do
      # Send 3 crashes with the same error pattern
      for i <- 1..3 do
        CrashLearner.report_crash(pid, "trial_#{i}", "KeyError: key :foo not found in %{bar: 1}")
      end
      :timer.sleep(30)

      {:ok, pitfalls} = CrashLearner.get_pitfalls(pid)
      assert length(pitfalls) >= 1

      pitfall = hd(pitfalls)
      assert pitfall.count >= 3
      assert String.contains?(pitfall.summary, "Recurring crash")
    end

    test "does not distill below threshold", %{pid: pid} do
      CrashLearner.report_crash(pid, "trial_1", "KeyError: key :foo not found")
      CrashLearner.report_crash(pid, "trial_2", "KeyError: key :foo not found")
      :timer.sleep(20)

      {:ok, pitfalls} = CrashLearner.get_pitfalls(pid)
      assert pitfalls == []
    end

    test "groups similar errors by stripping dynamic values", %{pid: pid} do
      # These errors differ only in numbers and PIDs
      CrashLearner.report_crash(pid, "t1", "timeout after 5000ms waiting for #PID<0.123.0>")
      CrashLearner.report_crash(pid, "t2", "timeout after 3000ms waiting for #PID<0.456.0>")
      CrashLearner.report_crash(pid, "t3", "timeout after 8000ms waiting for #PID<0.789.0>")
      :timer.sleep(30)

      {:ok, pitfalls} = CrashLearner.get_pitfalls(pid)
      assert length(pitfalls) >= 1
    end
  end

  describe "analyze_crash/4" do
    test "calls llm_fn with error and enriched context", %{pid: pid} do
      # First add a pitfall so context is enriched
      for i <- 1..3 do
        CrashLearner.report_crash(pid, "t#{i}", "known_pattern_error")
      end
      :timer.sleep(20)

      llm_fn = fn error, context ->
        assert error == "new crash"
        assert is_list(context.known_pitfalls)
        {:ok, "suggested fix: check your inputs"}
      end

      result = CrashLearner.analyze_crash(pid, "new crash", %{step: 5}, llm_fn)
      assert {:ok, "suggested fix: check your inputs"} = result
    end

    test "handles llm_fn errors gracefully", %{pid: pid} do
      llm_fn = fn _error, _context ->
        raise "LLM unavailable"
      end

      result = CrashLearner.analyze_crash(pid, "some error", %{}, llm_fn)
      assert {:error, "LLM unavailable"} = result
    end
  end

  describe "distill_pitfalls/2" do
    test "uses llm_fn to produce pitfalls from crashes", %{pid: pid} do
      CrashLearner.report_crash(pid, "t1", "error A")
      CrashLearner.report_crash(pid, "t2", "error B")
      :timer.sleep(20)

      llm_fn = fn crashes ->
        assert length(crashes) == 2
        {:ok, [
          %{pattern: "pattern_a", count: 1, summary: "LLM says: watch out for A"},
          %{pattern: "pattern_b", count: 1, summary: "LLM says: watch out for B"}
        ]}
      end

      {:ok, pitfalls} = CrashLearner.distill_pitfalls(pid, llm_fn)
      assert length(pitfalls) == 2
    end

    test "handles llm_fn error", %{pid: pid} do
      llm_fn = fn _crashes -> {:error, :timeout} end
      result = CrashLearner.distill_pitfalls(pid, llm_fn)
      assert {:error, :timeout} = result
    end
  end
end
