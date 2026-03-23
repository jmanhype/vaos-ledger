defmodule Vaos.Ledger.Experiment.ScorerTest do
  use ExUnit.Case

  alias Vaos.Ledger.Experiment.Scorer
  alias Vaos.Ledger.Epistemic.Models

  describe "score_result/2" do
    test "returns {:computed, score} tuple" do
      result = %{
        execution_record: Models.ExecutionRecord.new(
          status: :succeeded, runtime_seconds: 5.0
        ),
        eval_runs: [],
        content: "test content"
      }
      {status, score} = Scorer.score_result(result)
      assert status == :computed
      assert is_number(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "scores succeeded execution higher than failed" do
      succeeded = %{
        execution_record: Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 5.0),
        eval_runs: [],
        content: "ok"
      }
      failed = %{
        execution_record: Models.ExecutionRecord.new(status: :failed, runtime_seconds: 5.0),
        eval_runs: [],
        content: "err"
      }
      {_, score_good} = Scorer.score_result(succeeded)
      {_, score_bad} = Scorer.score_result(failed)
      assert score_good > score_bad
    end

    test "with fast: false returns :computed" do
      result = %{
        execution_record: Models.ExecutionRecord.new(status: :succeeded),
        eval_runs: [],
        content: "c"
      }
      {status, _score} = Scorer.score_result(result, fast: false)
      assert status == :computed
    end
  end

  describe "score_batch/2" do
    test "scores and sorts results descending" do
      results = [
        %{execution_record: Models.ExecutionRecord.new(status: :failed), eval_runs: [], content: "a"},
        %{execution_record: Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 2.0), eval_runs: [], content: "b"}
      ]
      batch = Scorer.score_batch(results)
      assert length(batch) == 2
      [{_, _, score1}, {_, _, score2}] = batch
      assert score1 >= score2
    end
  end

  describe "compute_quality_score/1" do
    test "returns weighted score" do
      metrics = %{
        correctness: 1.0,
        efficiency: 1.0,
        clarity: 1.0,
        novelty: 1.0,
        reproducibility: 1.0
      }
      assert Scorer.compute_quality_score(metrics) == 1.0
    end

    test "uses defaults for missing metrics" do
      score = Scorer.compute_quality_score(%{})
      assert_in_delta score, 0.5, 0.01
    end

    test "weights correctness highest" do
      high_correct = Scorer.compute_quality_score(%{correctness: 1.0})
      high_clarity = Scorer.compute_quality_score(%{clarity: 1.0})
      assert high_correct > high_clarity
    end
  end

  describe "estimate_score/2" do
    test "estimates from execution record and eval runs" do
      exec = Models.ExecutionRecord.new(
        status: :succeeded, runtime_seconds: 5.0, artifact_quality: 0.9
      )
      score = Scorer.estimate_score(exec, [])
      assert is_number(score)
      assert score >= 0.0 and score <= 1.0
    end

    test "incorporates eval run scores" do
      exec = Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 5.0)
      runs = [
        Models.EvalRun.new(score: 0.9, passed: true),
        Models.EvalRun.new(score: 0.8, passed: true)
      ]
      score = Scorer.estimate_score(exec, runs)
      assert score > 0.0
    end

    test "fast runtime gets bonus" do
      fast = Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 2.0)
      slow = Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 500.0)
      score_fast = Scorer.estimate_score(fast, [])
      score_slow = Scorer.estimate_score(slow, [])
      assert score_fast > score_slow
    end
  end
end
