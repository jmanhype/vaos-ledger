defmodule Vaos.Ledger.Experiment.Scorer do
  @moduledoc """
  Cheap LLM scoring for experiment results.
  Provides quality assessment without expensive re-running.
  """

  alias Vaos.Ledger.Epistemic.Models

  @type score_option :: {:fast, boolean()} | {:use_cache, boolean()}


  @doc """
  Score an experiment result.
  Returns a score between 0.0 and 1.0.
  """
  def score_result(result, opts \\ []) do
    fast = Keyword.get(opts, :fast, true)
    use_cache = Keyword.get(opts, :use_cache, true)

    if fast and use_cache do
      cache_key = cache_key(result)

      with {:ok, score} <- get_from_cache(cache_key) do
        {:cached, score}
      else
        _ -> {:computed, compute_score(result, opts)}
      end
    else
      {:computed, compute_score(result, opts)}
    end
  end

  @doc """
  Score multiple results in batch.
  """
  def score_batch(results, opts \\ []) do
    Enum.map(results, fn result ->
      {status, score} = score_result(result, opts)
      {result, status, score}
    end)
    |> Enum.sort_by(fn {_result, _status, score} -> score end, :desc)
  end

  @doc """
  Compute quality score from metrics.
  """
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
  Estimate score without LLM call.
  Uses heuristics based on execution metrics.
  """
  def estimate_score(execution_record, eval_runs) do
    # Factor in execution status
    base_score =
      case execution_record.status do
        :succeeded -> 0.8
        :failed -> 0.2
        :running -> 0.5
        _ -> 0.4
      end

    # Adjust for runtime
    runtime_factor =
      cond do
        is_nil(execution_record.runtime_seconds) -> 1.0
        execution_record.runtime_seconds < 10.0 -> 1.2
        execution_record.runtime_seconds < 60.0 -> 1.0
        execution_record.runtime_seconds < 300.0 -> 0.8
        true -> 0.6
      end

    # Adjust for artifact quality if available
    quality_factor =
      case execution_record.artifact_quality do
        nil -> 1.0
        q when q > 0.8 -> 1.1
        q when q > 0.6 -> 1.0
        q when q > 0.4 -> 0.8
        _ -> 0.6
      end

    # Adjust for eval run results if available
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

        (avg_score * 0.7 + pass_rate * 0.3)
      end

    Models.clamp(base_score * runtime_factor * quality_factor * eval_factor)
  end

  # Private functions

  defp compute_score(result, _opts) do
    # In a real implementation, this would call an LLM
    # For now, use heuristic estimation
    execution_record = Map.get(result, :execution_record)
    eval_runs = Map.get(result, :eval_runs, [])

    estimate_score(execution_record, eval_runs)
  end

  defp cache_key(result) do
    execution_record = Map.get(result, :execution_record)
    content = Map.get(result, :content, "")

    # Create a cache key based on content hash and execution status
    hash =
      :crypto.hash(:sha256, content <> Atom.to_string(execution_record.status))
      |> Base.encode16(case: :lower)

    "score:#{hash}"
  end

  defp get_from_cache(_key) do
    # In a real implementation, use ETS or other caching
    :miss
  end
end
