defmodule Vaos.Ledger.Experiment.Verdict do
  @moduledoc """
  Verdict module for >20% threshold logic.
  Determines when optimization results are sufficient.
  """

  @type threshold :: float()
  @type verdict :: :continue | :converged | :plateau

  @default_threshold 0.2

  @doc """
  Return true when best_score >= baseline_score * (1 + threshold).
  """
  @spec meets_threshold?(float(), float(), threshold()) :: boolean()
  def meets_threshold?(best_score, baseline_score \\ 0.0, threshold \\ @default_threshold) do
    best_score >= baseline_score * (1.0 + threshold)
  end

  @doc """
  Return true when best_score meets the threshold and
  candidate.score also meets the threshold.
  """
  @spec keep_candidate?(map(), float(), float(), threshold()) :: boolean()
  def keep_candidate?(candidate, best_score, baseline_score \\ 0.0, threshold \\ @default_threshold) do
    meets_threshold?(best_score, baseline_score, threshold) and
      candidate.score >= baseline_score * (1.0 + threshold)
  end

  @doc """
  Return :continue, :converged, or :plateau for an optimization run.
  """
  @spec verdict(float(), float(), float(), non_neg_integer(), pos_integer(), threshold()) :: verdict()
  def verdict(best_score, prev_best_score, baseline_score, iteration, max_iterations \\ 100, threshold \\ @default_threshold) do
    cond do
      iteration >= max_iterations ->
        :converged

      not meets_threshold?(best_score, baseline_score, threshold) ->
        :plateau

      abs(best_score - prev_best_score) < threshold * baseline_score ->
        :converged

      true ->
        :continue
    end
  end

  @doc """
  Keyword-args variant of `verdict/6`.

  ## Options
    * `:best` - current best score (required)
    * `:prev_best` - previous best score (required)
    * `:baseline` - baseline score (required)
    * `:iteration` - current iteration (required)
    * `:max_iterations` - max iterations (default: 100)
    * `:threshold` - improvement threshold (default: 0.2)

  ## Example

      Verdict.verdict(best: 9.0, prev_best: 7.0, baseline: 6.0, iteration: 5)

  """
  @spec verdict(keyword()) :: verdict()
  def verdict(opts) when is_list(opts) do
    best = Keyword.fetch!(opts, :best)
    prev_best = Keyword.fetch!(opts, :prev_best)
    baseline = Keyword.fetch!(opts, :baseline)
    iteration = Keyword.fetch!(opts, :iteration)
    max_iterations = Keyword.get(opts, :max_iterations, 100)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    verdict(best, prev_best, baseline, iteration, max_iterations, threshold)
  end

  @doc """
  Return the fractional improvement of new_score over baseline_score.
  Returns 0.0 when baseline_score is zero.
  """
  @spec improvement(float(), float()) :: float()
  def improvement(new_score, baseline_score) when baseline_score > 0 do
    (new_score - baseline_score) / baseline_score
  end

  def improvement(_new_score, _baseline_score), do: 0.0

  @doc """
  Format a verdict atom as a human-readable string with improvement percentage.
  """
  @spec format_verdict(verdict(), float(), float()) :: String.t()
  def format_verdict(:continue, score, baseline), do: "Continuing (" <> format_improvement(score, baseline) <> ")"
  def format_verdict(:converged, score, baseline), do: "Converged (" <> format_improvement(score, baseline) <> ")"
  def format_verdict(:plateau, score, baseline), do: "Plateau reached (" <> format_improvement(score, baseline) <> ")"

  defp format_improvement(score, baseline) when baseline > 0 do
    pct = improvement(score, baseline) * 100
    :erlang.float_to_binary(pct, decimals: 2) <> "%"
  end

  defp format_improvement(_score, _baseline), do: "N/A"
end
