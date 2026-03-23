defmodule Vaos.Ledger.Research.PipelineTest do
  use ExUnit.Case

  alias Vaos.Ledger.Research.Pipeline
  alias Vaos.Ledger.Epistemic.{Ledger, Models}

  setup do
    if pid = GenServer.whereis(Ledger) do
      GenServer.stop(pid)
    end

    path = Path.join(System.tmp_dir!(), "pipeline_test_#{:rand.uniform(999999)}.json")
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

  describe "generate_idea/2" do
    test "creates hypothesis from input artifact" do
      input = Models.InputArtifact.new(
        title: "Paper X", input_type: "paper",
        content: "content", summary: "A summary"
      )
      {:ok, hypothesis} = Pipeline.generate_idea(Ledger, input)
      assert String.contains?(hypothesis.title, "Paper X")
      assert hypothesis.input_id == input.id
    end
  end

  describe "develop_method/2" do
    test "creates method artifact from hypothesis" do
      hyp = Models.InnovationHypothesis.new(
        title: "Test Hypothesis", statement: "Investigate X"
      )
      {:ok, method} = Pipeline.develop_method(Ledger, hyp)
      assert method.kind == :method
      assert String.contains?(method.title, "Test Hypothesis")
    end
  end

  describe "run_experiments/4" do
    test "generates candidates and evaluates them" do
      method = Models.Artifact.new(
        claim_id: "", kind: :method, title: "Method 1", content: "code"
      )
      target = Models.ArtifactTarget.new(
        claim_id: "", mode: "opt", target_type: "code", title: "Target 1"
      )
      suite = Models.EvalSuite.new(
        claim_id: "", target_id: target.id, name: "Suite",
        compatible_target_type: "code"
      )

      {:ok, results} = Pipeline.run_experiments(Ledger, method, target, suite)
      assert length(results) == 3
      assert Enum.all?(results, &Map.has_key?(&1, :score))
      assert Enum.all?(results, &Map.has_key?(&1, :candidate))
    end
  end

  describe "synthesize_paper/3" do
    test "creates paper artifact from results" do
      hyp = Models.InnovationHypothesis.new(
        title: "Test Hypothesis", statement: "Statement"
      )
      results = [
        %{candidate_id: "c1", score: 0.9, eval_run: nil, candidate: nil},
        %{candidate_id: "c2", score: 0.7, eval_run: nil, candidate: nil}
      ]
      {:ok, paper} = Pipeline.synthesize_paper(Ledger, results, hyp)
      assert paper.kind == :paper
      assert String.contains?(paper.content, "0.9")
    end
  end

  describe "run/1" do
    test "runs full pipeline with callbacks" do
      llm_fn = fn _prompt -> {:ok, "TITLE: Test\n\nIDEA: Test idea\n\nRATIONALE: Test"} end

      {:ok, state} = Pipeline.run(
        ledger: Ledger,
        llm_fn: llm_fn,
        input: "Test research topic",
        max_iterations: 4
      )
      assert state.status == :completed
      assert state.iteration == 4
    end
  end
end
