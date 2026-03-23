defmodule Vaos.Ledger.Experiment.Scorer do
  @moduledoc """
  Cheap LLM scoring for experiment results.
  Provides quality assessment without expensive re-running.
  """

  require Logger

  alias Vaos.Ledger.Epistemic.Models

  @type score_option :: {:fast, boolean()} | {:use_cache, boolean()} | {:llm_fn, (String.t() -> {:ok, String.t()} | {:error, term()})}
  @type score_result :: {:cached | :computed, float()}

  @doc """
  Score an experiment result map.

  Returns `{:cached, score}` when a cached score is found, or
  `{:computed, score}` otherwise.  The result map must contain at least
  `:execution_record`.

  ## Options
    * `:fast` — use caching (default `true`)
    * `:use_cache` — consult in-memory cache (default `true`)
    * `:llm_fn` — optional callback `(String.t() -> {:ok, String.t()} | {:error, term()})`.
      If provided, uses the LLM to score the result. Falls back to estimation on failure.
  """
  @spec score_result(map(), list(score_option())) :: score_result()
  def score_result(result, opts \\ []) do
    fast = Keyword.get(opts, :fast, true)
    use_cache = Keyword.get(opts, :use_cache, true)

    if fast and use_cache do
      init_cache()
      cache_key = cache_key(result)

      case get_from_cache(cache_key) do
        {:ok, score} ->
          {:cached, score}

        :miss ->
          score = compute_score(result, opts)
          put_in_cache(cache_key, score)
          {:computed, score}
      end
    else
      {:computed, compute_score(result, opts)}
    end
  end

  @doc """
  Score multiple results in batch.

  Returns a list of `{result, status, score}` tuples sorted descending by
  score.
  """
  @spec score_batch(list(map()), list(score_option())) :: list({map(), atom(), float()})
  def score_batch(results, opts \\ []) do
    results
    |> Enum.map(fn result ->
      {status, score} = score_result(result, opts)
      {result, status, score}
    end)
    |> Enum.sort_by(fn {_result, _status, score} -> score end, :desc)
  end

  @doc """
  Compute a composite quality score from a metrics map.

  Keys: `:correctness`, `:efficiency`, `:clarity`, `:novelty`,
  `:reproducibility`.  Missing keys default to 0.5.

  Returns a float in `[0.0, 1.0]`.
  """
  @spec compute_quality_score(map()) :: float()
  def compute_quality_score(metrics) do
    weights = %{
      correctness: 0.35,
      efficiency: 0.20,
      clarity: 0.15,
      novelty: 0.15,
      reproducibility: 0.15
    }

    correctness_score = Map.get(metrics, :correctness, 0.5)
    efficiency_score = Map.get(metrics, :efficiency, 0.5)
    clarity_score = Map.get(metrics, :clarity, 0.5)
    novelty_score = Map.get(metrics, :novelty, 0.5)
    reproducibility_score = Map.get(metrics, :reproducibility, 0.5)

    weights.correctness * correctness_score +
      weights.efficiency * efficiency_score +
      weights.clarity * clarity_score +
      weights.novelty * novelty_score +
      weights.reproducibility * reproducibility_score
  end

  @doc """
  Estimate score from an execution record and optional eval runs, without
  making an LLM call.

  Factors: execution status, runtime, artifact quality, eval run scores.
  Returns a float in `[0.0, 1.0]`.
  """
  @spec estimate_score(Models.ExecutionRecord.t() | map(), list()) :: float()
  def estimate_score(execution_record, eval_runs) do
    base_score =
      case execution_record.status do
        :succeeded -> 0.8
        :failed -> 0.2
        :running -> 0.5
        _ -> 0.4
      end

    runtime_factor =
      cond do
        is_nil(execution_record.runtime_seconds) -> 1.0
        execution_record.runtime_seconds < 10.0 -> 1.2
        execution_record.runtime_seconds < 60.0 -> 1.0
        execution_record.runtime_seconds < 300.0 -> 0.8
        true -> 0.6
      end

    quality_factor =
      case execution_record.artifact_quality do
        nil -> 1.0
        q when q > 0.8 -> 1.1
        q when q > 0.6 -> 1.0
        q when q > 0.4 -> 0.8
        _ -> 0.6
      end

    eval_factor =
      if Enum.empty?(eval_runs) do
        1.0
      else
        avg_score =
          eval_runs
          |> Enum.map(& &1.score)
          |> Enum.sum()
          |> (&(&1 / length(eval_runs))).()

        pass_rate =
          eval_runs
          |> Enum.count(& &1.passed)
          |> (&(&1 / length(eval_runs))).()

        avg_score * 0.7 + pass_rate * 0.3
      end

    Models.clamp(base_score * runtime_factor * quality_factor * eval_factor)
  end

  # Private functions

  defp compute_score(result, opts) do
    llm_fn = Keyword.get(opts, :llm_fn)
    execution_record = Map.get(result, :execution_record)
    eval_runs = Map.get(result, :eval_runs, [])

    if llm_fn do
      score_with_llm(result, llm_fn, execution_record, eval_runs)
    else
      estimate_score(execution_record, eval_runs)
    end
  end

  defp score_with_llm(result, llm_fn, execution_record, eval_runs) do
    content = Map.get(result, :content, "")
    status = execution_record.status

    prompt = """
    Score the following experiment result on a scale of 0.0 to 1.0.
    Consider correctness, efficiency, and quality.

    Status: #{status}
    Content: #{String.slice(content, 0, 500)}

    Respond with just a number between 0.0 and 1.0.
    """

    case llm_fn.(prompt) do
      {:ok, response} ->
        trimmed = String.trim(response)

        case Float.parse(trimmed) do
          {score, _} ->
            Vaos.Ledger.Epistemic.Models.clamp(score)

          :error ->
            Logger.warning("LLM score response did not start with a number: " <> inspect(String.slice(trimmed, 0, 100)))
            estimate_score(execution_record, eval_runs)
        end

      {:error, reason} ->
        Logger.warning("LLM scoring call failed: " <> inspect(reason))
        estimate_score(execution_record, eval_runs)
    end
  end

  defp cache_key(result) do
    execution_record = Map.get(result, :execution_record)
    content = Map.get(result, :content, "")

    hash =
      :crypto.hash(:sha256, content <> Atom.to_string(execution_record.status))
      |> Base.encode16(case: :lower)

    "score:#{hash}"
  end

  defp init_cache do
    if :ets.whereis(:scorer_cache) == :undefined do
      :ets.new(:scorer_cache, [:set, :public, :named_table])
    end

    :ok
  end

  defp get_from_cache(key) do
    case :ets.whereis(:scorer_cache) do
      :undefined ->
        :miss

      _table ->
        case :ets.lookup(:scorer_cache, key) do
          [{^key, score}] -> {:ok, score}
          [] -> :miss
        end
    end
  end

  defp put_in_cache(key, score) do
    case :ets.whereis(:scorer_cache) do
      :undefined -> :ok
      _table -> :ets.insert(:scorer_cache, {key, score})
    end
  end
end
