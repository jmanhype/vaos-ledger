defmodule Vaos.Ledger.DogfoodFixesTest do
  @moduledoc """
  Tests for the 7 API issues found during dogfooding.
  """
  use ExUnit.Case

  alias Vaos.Ledger.Epistemic.Ledger
  alias Vaos.Ledger.Epistemic.Models
  alias Vaos.Ledger.Experiment.{Scorer, Verdict}
  alias Vaos.Ledger.Research.{Pipeline, Paper}

  setup do
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end

    path = Path.join(System.tmp_dir!(), "dogfood_test_#{:rand.uniform(999999)}.json")
    {:ok, _pid} = Ledger.start_link(path: path)

    on_exit(fn ->
      try do
        if pid = GenServer.whereis(Ledger), do: GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm(path)
    end)

    %{path: path}
  end

  describe "Fix 1: add_assumption accepts :statement" do
    test "normalizes :statement to :text" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      assumption = Ledger.add_assumption(claim_id: claim.id, statement: "Assume via statement")
      assert assumption.text == "Assume via statement"
    end

    test ":text still works as before" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      assumption = Ledger.add_assumption(claim_id: claim.id, text: "Assume via text")
      assert assumption.text == "Assume via text"
    end

    test ":text takes precedence over :statement" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      assumption = Ledger.add_assumption(claim_id: claim.id, text: "text wins", statement: "statement loses")
      assert assumption.text == "text wins"
    end
  end

  describe "Fix 2: add_attack accepts :statement" do
    test "normalizes :statement to :description" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      attack = Ledger.add_attack(claim_id: claim.id, statement: "Attack via statement")
      assert attack.description == "Attack via statement"
    end

    test ":description still works as before" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      attack = Ledger.add_attack(claim_id: claim.id, description: "Attack via desc")
      assert attack.description == "Attack via desc"
    end

    test ":description takes precedence over :statement" do
      claim = Ledger.add_claim(title: "T", statement: "S")
      attack = Ledger.add_attack(claim_id: claim.id, description: "desc wins", statement: "loses")
      assert attack.description == "desc wins"
    end
  end

  describe "Fix 3: Verdict keyword-args variant" do
    test "accepts keyword list" do
      result = Verdict.verdict(best: 1.8, prev_best: 1.2, baseline: 1.0, iteration: 5)
      assert result == :continue
    end

    test "keyword variant matches positional" do
      positional = Verdict.verdict(1.8, 1.2, 1.0, 5, 100, 0.2)
      keyword = Verdict.verdict(best: 1.8, prev_best: 1.2, baseline: 1.0, iteration: 5, max_iterations: 100, threshold: 0.2)
      assert positional == keyword
    end

    test "keyword variant uses defaults" do
      result = Verdict.verdict(best: 0.1, prev_best: 0.09, baseline: 1.0, iteration: 5)
      assert result == :plateau
    end
  end

  describe "Fix 4: Scorer with llm_fn callback" do
    test "uses llm_fn when provided" do
      result = %{
        execution_record: Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 5.0),
        eval_runs: [],
        content: "test content"
      }

      llm_fn = fn _prompt -> {:ok, "0.95"} end
      {status, score} = Scorer.score_result(result, fast: false, llm_fn: llm_fn)
      assert status == :computed
      assert_in_delta score, 0.95, 0.01
    end

    test "falls back to estimation when llm_fn fails" do
      result = %{
        execution_record: Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 5.0),
        eval_runs: [],
        content: "test"
      }

      llm_fn = fn _prompt -> {:error, :api_down} end
      {status, score} = Scorer.score_result(result, fast: false, llm_fn: llm_fn)
      assert status == :computed
      assert score > 0.0
    end

    test "falls back when llm_fn returns non-numeric" do
      result = %{
        execution_record: Models.ExecutionRecord.new(status: :succeeded, runtime_seconds: 5.0),
        eval_runs: [],
        content: "test"
      }

      llm_fn = fn _prompt -> {:ok, "not a number"} end
      {status, score} = Scorer.score_result(result, fast: false, llm_fn: llm_fn)
      assert status == :computed
      assert score > 0.0
    end
  end

  describe "Fix 5: Pipeline.run requires :input with clear error" do
    test "raises ArgumentError when :input is missing" do
      llm_fn = fn _prompt -> {:ok, "response"} end

      assert_raise ArgumentError, ~r/Pipeline\.run requires :input/, fn ->
        Pipeline.run(ledger: Ledger, llm_fn: llm_fn)
      end
    end
  end

  describe "Fix 6: Paper output is a struct" do
    test "synthesize returns a Paper struct" do
      llm_fn = fn prompt ->
        cond do
          String.contains?(prompt, "title and abstract") ->
            {:ok, "TITLE: Test\n\nABSTRACT: Abstract text"}
          String.contains?(prompt, "Introduction") ->
            {:ok, "Intro section"}
          String.contains?(prompt, "Methods") ->
            {:ok, "Methods section"}
          String.contains?(prompt, "Results") ->
            {:ok, "Results section"}
          String.contains?(prompt, "Conclusions") ->
            {:ok, "Conclusions section"}
          String.contains?(prompt, "keywords") ->
            {:ok, "AI, ML"}
          true ->
            {:ok, "default"}
        end
      end

      context = %{idea: "idea", methodology: "method", results: "results", literature: "lit"}
      {:ok, paper} = Paper.synthesize(context, llm_fn)
      assert %Paper{} = paper
      assert paper.title == "Test"
      assert paper.abstract == "Abstract text"
      assert is_list(paper.bibliography)
    end
  end

  describe "Fix 7: Ledger name is configurable" do
    test "can start multiple named instances" do
      path1 = Path.join(System.tmp_dir!(), "named_ledger_1_#{:rand.uniform(999999)}.json")
      path2 = Path.join(System.tmp_dir!(), "named_ledger_2_#{:rand.uniform(999999)}.json")

      {:ok, pid1} = Ledger.start_link(path: path1, name: :ledger_one)
      {:ok, pid2} = Ledger.start_link(path: path2, name: :ledger_two)

      assert is_pid(pid1)
      assert is_pid(pid2)
      assert pid1 != pid2

      GenServer.stop(pid1)
      GenServer.stop(pid2)
      File.rm(path1)
      File.rm(path2)
    end
  end
end
