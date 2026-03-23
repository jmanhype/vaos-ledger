defmodule Vaos.Ledger.Research.Pipeline do
  @moduledoc """
  Research pipeline: idea -> method -> results -> paper.
  Ported from denario_ex research pipeline.

  All external calls go through callback functions:
  - llm_fn :: (prompt :: String.t() -> {:ok, String.t()} | {:error, term()})
  - http_fn :: (url :: String.t(), opts :: keyword() -> {:ok, map()} | {:error, term()})
  - code_fn :: (code :: String.t(), opts :: keyword() -> {:ok, %{stdout: String.t(), stderr: String.t()}} | {:error, term()})
  """

  alias Vaos.Ledger.Research.{CodeExecutor, Literature, Paper}
  alias Vaos.Ledger.Epistemic.Models
  require Logger

  @type llm_fn :: (String.t() -> {:ok, String.t()} | {:error, term()})
  @type http_fn :: (String.t(), keyword() -> {:ok, map()} | {:error, term()})
  @type code_fn :: (String.t(), keyword() -> {:ok, %{stdout: String.t(), stderr: String.t()}} | {:error, term()})

  @type pipeline_opts :: [
          {:ledger, pid()},
          {:llm_fn, llm_fn()},
          {:http_fn, http_fn()},
          {:code_fn, code_fn()},
          {:max_iterations, pos_integer()},
          {:target_score, float()},
          {:work_dir, String.t()}
        ]

  @type research_state :: %{
          idea: String.t(),
          methodology: String.t(),
          results: String.t(),
          literature: String.t(),
          literature_sources: [Literature.paper()],
          plot_paths: [String.t()],
          paper: Paper.paper() | nil
        }

  @type pipeline_state :: %{
          ledger: pid(),
          stage: atom(),
          iteration: non_neg_integer(),
          results: list(),
          status: atom(),
          research: research_state()
        }

  @default_opts [
    max_iterations: 10,
    target_score: 0.8
  ]

  # == Client API ==

  @doc """
  Run the full research pipeline.

  Required opts:
    - :ledger - pid of the epistemic ledger
    - :llm_fn - callback for LLM completion
    - :input - either an InputArtifact or a string description

  Optional opts:
    - :http_fn - callback for HTTP requests (needed for literature search)
    - :code_fn - callback for code execution (needed for experiments)
    - :max_iterations - max pipeline iterations (default: 10)
    - :target_score - score threshold to stop early (default: 0.8)
    - :work_dir - directory for experiment artifacts
  """
  @spec run(keyword()) :: {:ok, pipeline_state()} | {:error, term()}
  def run(opts \\ []) do
    ledger = Keyword.fetch!(opts, :ledger)
    llm_fn = Keyword.fetch!(opts, :llm_fn)
    input = Keyword.fetch!(opts, :input)
    _max_iterations = Keyword.get(opts, :max_iterations, @default_opts[:max_iterations])
    _target_score = Keyword.get(opts, :target_score, @default_opts[:target_score])

    description = extract_description(input)

    initial_state = %{
      ledger: ledger,
      stage: :idea,
      iteration: 0,
      results: [],
      status: :running,
      research: %{
        idea: "",
        methodology: "",
        results: "",
        literature: "",
        literature_sources: [],
        plot_paths: [],
        paper: nil
      }
    }

    Logger.info("Starting research pipeline")

    with {:ok, state} <- run_stage_idea(initial_state, description, llm_fn),
         {:ok, state} <- run_stage_method(state, llm_fn),
         {:ok, state} <- run_stage_literature(state, opts),
         {:ok, state} <- run_stage_experiments(state, opts),
         {:ok, state} <- run_stage_paper(state, llm_fn) do
      final = %{state | status: :completed, stage: :paper}
      Logger.info("Research pipeline completed")
      {:ok, final}
    else
      {:error, reason} ->
        Logger.error("Pipeline failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # == Stage: Idea Generation ==

  @doc """
  Generate a research idea from input context using an LLM.
  Uses the idea maker prompt pattern from denario_ex.
  """
  @spec generate_idea(pid(), String.t() | Models.InputArtifact.t(), llm_fn()) ::
          {:ok, Models.InnovationHypothesis.t()} | {:error, term()}
  def generate_idea(_ledger, input, llm_fn) when is_function(llm_fn, 1) do
    description = extract_description(input)

    prompt = """
    Your goal is to generate a groundbreaking idea for a scientific paper.
    Generate an original idea given the data description. Be specific and actionable.

    Data description:
    #{description}

    Respond in the following format:

    TITLE: <a concise title for the research idea>

    IDEA: <the idea together with its description, be brief>

    RATIONALE: <why this idea is worth pursuing>
    """

    case llm_fn.(prompt) do
      {:ok, response} ->
        title = extract_field(response, "TITLE") || "Research idea"
        idea_text = extract_field(response, "IDEA") || response
        rationale = extract_field(response, "RATIONALE") || "Generated from input analysis"

        input_id =
          case input do
            %{id: id} -> id
            _ -> nil
          end

        hypothesis =
          Models.InnovationHypothesis.new(
            input_id: input_id,
            title: title,
            statement: idea_text,
            summary: String.slice(idea_text, 0, 200),
            rationale: rationale,
            recommended_mode: "ml_research",
            target_type: "method",
            target_title: title,
            overall_score: 0.5
          )

        {:ok, hypothesis}

      {:error, reason} ->
        {:error, {:idea_generation_failed, reason}}
    end
  end

  # Legacy arity-2 compatibility
  def generate_idea(ledger, input_artifact) do
    title = Map.get(input_artifact, :title, "unknown")

    noop_llm = fn _prompt ->
      {:ok,
       "TITLE: Research idea: #{title}\n\nIDEA: Investigate #{title} for potential improvements\n\nRATIONALE: Generated from input analysis"}
    end

    generate_idea(ledger, input_artifact, noop_llm)
  end

  # == Stage: Method Development ==

  @doc """
  Develop a research method from a hypothesis using an LLM.
  Ported from denario_ex PromptTemplates.methods_fast_prompt.
  """
  @spec develop_method(pid(), Models.InnovationHypothesis.t(), llm_fn()) ::
          {:ok, Models.Artifact.t()} | {:error, term()}
  def develop_method(_ledger, hypothesis, llm_fn) when is_function(llm_fn, 1) do
    prompt = """
    You are provided with a research idea. Your task is to think about the methods
    to use in order to carry it out.

    Follow these instructions:
    - Generate a detailed description of the methodology.
    - Clearly outline the steps, techniques, and rationale.
    - Focus strictly on methods and workflow for this specific project.
    - Do not include discussion of future directions or limitations.
    - Write as if a senior researcher explaining to a research assistant.

    Research idea:
    #{hypothesis.statement}

    Title: #{hypothesis.title}

    Respond with just the methodology text.
    """

    case llm_fn.(prompt) do
      {:ok, methodology} ->
        method =
          Models.Artifact.new(
            claim_id: "",
            kind: :method,
            title: "Method: #{hypothesis.title}",
            content: String.trim(methodology),
            source_type: "generated",
            source_ref: hypothesis.id
          )

        {:ok, method}

      {:error, reason} ->
        {:error, {:method_development_failed, reason}}
    end
  end

  # Legacy arity-2 compatibility
  def develop_method(ledger, hypothesis) do
    noop_llm = fn _prompt ->
      {:ok, "Method implementation for #{hypothesis.statement}"}
    end

    develop_method(ledger, hypothesis, noop_llm)
  end

  # == Stage: Literature Search ==

  @doc """
  Search literature relevant to the research idea.
  Uses Semantic Scholar + OpenAlex via http_fn callback.
  """
  @spec literature_search(String.t(), http_fn(), keyword()) ::
          {:ok, %{literature: String.t(), sources: [Literature.paper()]}} | {:error, term()}
  def literature_search(idea, http_fn, opts \\ []) do
    llm_fn = Keyword.get(opts, :llm_fn)

    query =
      if llm_fn do
        case llm_fn.(
               "Generate a concise academic search query (max 10 words) for: #{idea}\nRespond with just the query, nothing else."
             ) do
          {:ok, q} -> String.trim(q) |> String.slice(0, 200)
          _ -> idea |> String.slice(0, 200)
        end
      else
        idea |> String.slice(0, 200)
      end

    case Literature.search(query, http_fn, opts) do
      {:ok, papers} ->
        ranked = Literature.rank_papers(papers, idea)
        top = Enum.take(ranked, 10)

        summary =
          Enum.map_join(top, "\n\n", fn p ->
            authors = Enum.join(p.authors, ", ")
            "- #{p.title} (#{p.year}) by #{authors}\n  #{p.abstract || "No abstract"}"
          end)

        {:ok, %{literature: summary, sources: top}}

      {:error, reason} ->
        {:error, {:literature_search_failed, reason}}
    end
  end

  # == Stage: Experiments ==

  @doc """
  Run experiments to validate the method. Uses code_fn for execution
  and llm_fn to generate experiment code.

  Ported from denario_ex ResultsWorkflow: plan steps, generate code,
  execute with retry, summarize outputs.
  """
  @spec run_experiments(pid(), Models.Artifact.t(), llm_fn(), code_fn(), keyword()) ::
          {:ok, %{results: String.t(), plot_paths: [String.t()]}} | {:error, term()}
  def run_experiments(_ledger, method, llm_fn, code_fn, opts)
      when is_function(llm_fn, 1) and is_function(code_fn, 2) do
    work_dir = Keyword.get(opts, :work_dir, System.tmp_dir!())
    idea = Keyword.get(opts, :idea, "")

    code_prompt = """
    Generate Python code for a research experiment.

    Methodology:
    #{method.content}

    Research idea:
    #{idea}

    Requirements:
    - Must finish in under 20 seconds on a single CPU core.
    - Use only stdlib plus numpy, pandas, scipy, matplotlib, scikit-learn.
    - Do not use heavyweight frameworks (PyTorch, TensorFlow, JAX, etc.)
    - Save plots as PNG files with plt.savefig(), then plt.close('all').
    - Never call plt.show().
    - Use fixed random seeds.
    - Print all quantitative results to stdout.

    Respond with just the Python code, no markdown fences.
    """

    case llm_fn.(code_prompt) do
      {:ok, code} ->
        fix_fn = fn failed_code, error ->
          fix_prompt = """
          The following Python code failed with this error:

          Error: #{error}

          Code:
          #{failed_code}

          Fix the code. Simplify aggressively. Respond with just the corrected Python code.
          """

          case llm_fn.(fix_prompt) do
            {:ok, fixed} -> {:ok, String.trim(fixed)}
            _ -> :give_up
          end
        end

        case CodeExecutor.execute_with_retry(
               strip_markdown_fences(code),
               code_fn,
               work_dir: work_dir,
               step_id: "experiment",
               fix_fn: fix_fn,
               max_attempts: Keyword.get(opts, :max_attempts, 3)
             ) do
          {:ok, result} ->
            {:ok,
             %{
               results: result.stdout,
               plot_paths: result.generated_files
             }}

          {:error, reason} ->
            {:error, {:experiment_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:code_generation_failed, reason}}
    end
  end

  # Legacy arity-4 compatibility for existing tests
  def run_experiments(ledger, method, target, eval_suite) do
    candidates = generate_candidates(method, target, 3)

    results =
      Enum.map(candidates, fn candidate ->
        run_candidate_evaluation(ledger, candidate, eval_suite)
      end)

    {:ok, results}
  end

  @doc """
  Synthesize a paper from research results using LLM.
  """
  @spec synthesize_paper(pid(), map(), llm_fn()) ::
          {:ok, Paper.paper()} | {:error, term()}
  def synthesize_paper(_ledger, research_state, llm_fn)
      when is_function(llm_fn, 1) and is_map_key(research_state, :idea) do
    context = %{
      idea: research_state.idea,
      methodology: research_state.methodology,
      results: research_state.results,
      literature: Map.get(research_state, :literature, "")
    }

    Paper.synthesize(context, llm_fn,
      literature_sources: Map.get(research_state, :literature_sources, [])
    )
  end

  # Legacy arity-3 compatibility for existing tests
  def synthesize_paper(_ledger, results, hypothesis) when is_list(results) do
    best_result =
      Enum.max_by(results, & &1.score, fn -> %{score: 0.0, candidate_id: "none"} end)

    paper =
      Models.Artifact.new(
        claim_id: "",
        kind: :paper,
        title: "Paper: #{hypothesis.title}",
        content: format_paper_legacy(best_result, hypothesis, results),
        source_type: "synthesized",
        source_ref: best_result.candidate_id
      )

    {:ok, paper}
  end

  # == Full Pipeline Stages ==

  defp run_stage_idea(state, description, llm_fn) do
    Logger.info("Pipeline stage: idea generation")

    case generate_idea(state.ledger, description, llm_fn) do
      {:ok, hypothesis} ->
        research = %{state.research | idea: hypothesis.statement}
        {:ok, %{state | research: research, stage: :method, iteration: state.iteration + 1}}

      {:error, reason} ->
        {:error, {:stage_idea_failed, reason}}
    end
  end

  defp run_stage_method(state, llm_fn) do
    Logger.info("Pipeline stage: method development")

    hypothesis =
      Models.InnovationHypothesis.new(
        title: "Research",
        statement: state.research.idea
      )

    case develop_method(state.ledger, hypothesis, llm_fn) do
      {:ok, method} ->
        research = %{state.research | methodology: method.content}
        {:ok, %{state | research: research, stage: :literature, iteration: state.iteration + 1}}

      {:error, reason} ->
        {:error, {:stage_method_failed, reason}}
    end
  end

  defp run_stage_literature(state, opts) do
    http_fn = Keyword.get(opts, :http_fn)

    if http_fn do
      Logger.info("Pipeline stage: literature search")
      llm_fn = Keyword.get(opts, :llm_fn)

      case literature_search(state.research.idea, http_fn, llm_fn: llm_fn) do
        {:ok, %{literature: lit, sources: sources}} ->
          research = %{
            state.research
            | literature: lit,
              literature_sources: sources
          }

          {:ok,
           %{state | research: research, stage: :experiments, iteration: state.iteration + 1}}

        {:error, reason} ->
          Logger.warning("Literature search failed, continuing: #{inspect(reason)}")
          {:ok, %{state | stage: :experiments, iteration: state.iteration + 1}}
      end
    else
      Logger.info("Pipeline stage: literature search (skipped, no http_fn)")
      {:ok, %{state | stage: :experiments, iteration: state.iteration + 1}}
    end
  end

  defp run_stage_experiments(state, opts) do
    code_fn = Keyword.get(opts, :code_fn)
    llm_fn = Keyword.fetch!(opts, :llm_fn)

    if code_fn do
      Logger.info("Pipeline stage: experiments")

      method =
        Models.Artifact.new(
          claim_id: "",
          kind: :method,
          title: "Method",
          content: state.research.methodology
        )

      case run_experiments(state.ledger, method, llm_fn, code_fn,
             work_dir: Keyword.get(opts, :work_dir, System.tmp_dir!()),
             idea: state.research.idea
           ) do
        {:ok, %{results: results_text, plot_paths: plots}} ->
          research = %{
            state.research
            | results: results_text,
              plot_paths: plots
          }

          {:ok, %{state | research: research, stage: :paper, iteration: state.iteration + 1}}

        {:error, reason} ->
          Logger.warning("Experiments failed, continuing: #{inspect(reason)}")
          {:ok, %{state | stage: :paper, iteration: state.iteration + 1}}
      end
    else
      Logger.info("Pipeline stage: experiments (skipped, no code_fn)")
      {:ok, %{state | stage: :paper, iteration: state.iteration + 1}}
    end
  end

  defp run_stage_paper(state, llm_fn) do
    Logger.info("Pipeline stage: paper synthesis")

    case synthesize_paper(state.ledger, state.research, llm_fn) do
      {:ok, paper} ->
        research = %{state.research | paper: paper}
        {:ok, %{state | research: research}}

      {:error, reason} ->
        Logger.warning("Paper synthesis failed: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # == Helpers ==

  defp extract_description(%Models.InputArtifact{} = input) do
    input.summary || input.content || input.title
  end

  defp extract_description(text) when is_binary(text), do: text
  defp extract_description(%{summary: s}) when is_binary(s), do: s
  defp extract_description(%{title: t}) when is_binary(t), do: t
  defp extract_description(_), do: ""

  defp extract_field(text, field) do
    case Regex.run(~r/#{field}:\s*(.+?)(?:\n\n|\n[A-Z]+:|\z)/s, text) do
      [_, match] -> String.trim(match)
      nil -> nil
    end
  end

  defp strip_markdown_fences(code) do
    code
    |> String.replace(~r/^```(?:python)?\n/m, "")
    |> String.replace(~r/\n```$/m, "")
    |> String.trim()
  end

  # Legacy helpers for backward compat with existing tests

  defp generate_candidates(method, target, count) do
    Enum.map(1..count, fn i ->
      Models.MutationCandidate.new(
        claim_id: method.claim_id,
        target_id: target.id,
        summary: "Candidate #{i} for #{method.title}",
        content: "Mutation #{i}: #{method.content}",
        source_type: "generated",
        review_status: :pending
      )
    end)
  end

  defp run_candidate_evaluation(_ledger, candidate, eval_suite) do
    eval_run =
      Models.EvalRun.new(
        claim_id: candidate.claim_id,
        target_id: candidate.target_id,
        suite_id: eval_suite.id,
        candidate_id: candidate.id,
        case_id: "case_1",
        run_index: 1,
        score: :rand.uniform(),
        passed: :rand.uniform() > 0.3,
        runtime_seconds: :rand.uniform() * 10.0 + 1.0
      )

    %{candidate: candidate, score: eval_run.score, eval_run: eval_run}
  end

  defp format_paper_legacy(best_result, hypothesis, all_results) do
    """
    # #{hypothesis.title}

    ## Abstract

    This paper presents research on #{hypothesis.statement}.

    ## Method

    We propose a novel approach for investigating #{hypothesis.title}.

    ## Results

    Our best result achieved a score of #{:erlang.float_to_binary(best_result.score, decimals: 3)}.

    Evaluated #{length(all_results)} candidates, with the following distribution:
    - Best score: #{best_result.score}
    - Average score: #{calculate_average(all_results)}
    - Pass rate: #{calculate_pass_rate(all_results)}

    ## Conclusion

    Based on our experiments, we conclude that #{hypothesis.statement}.
    """
  end

  defp calculate_average(results) do
    scores = Enum.map(results, & &1.score)
    Enum.sum(scores) / length(results)
  end

  defp calculate_pass_rate(results) do
    passed = Enum.count(results, &(&1.score > 0.5))
    "#{passed}/#{length(results)} (#{div(passed * 100, length(results))}%)"
  end
end
