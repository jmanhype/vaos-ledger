defmodule Vaos.Ledger.Experiment.Verdict do
  @moduledoc """
  Verdict module for >20% threshold logic.
  Determines when optimization results are sufficient.
  """

  @type threshold :: float()

  @default_threshold 0.2

  @doc """
  Check if improvement exceeds threshold.
  Returns true if best_score >= baseline * (1 + threshold).
  """
  def meets_threshold?(best_score, baseline_score \\ 0.0, threshold \\ @default_threshold) do
    best_score >= baseline_score * (1.0 + threshold)
  end

  @doc """
  Check if candidate should be kept based on threshold.
  """
  def keep_candidate?(candidate, best_score, baseline_score \\ 0.0, threshold \\ @default_threshold) do
    meets_threshold?(best_score, baseline_score, threshold) and
      candidate.score >= baseline_score * (1.0 + threshold)
  end

  @doc """
  Get verdict for optimization run.
  Returns :continue, :converged, or :plateau.
  """
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
  Get improvement percentage.
  """
  def improvement(new_score, baseline_score) when baseline_score > 0 do
    (new_score - baseline_score) / baseline_score
  end

  def improvement(_new_score, _baseline_score), do: 0.0

  @doc """
  Format verdict for reporting.
  """
  def format_verdict(:continue, score, baseline), do: "Continuing (#{format_improvement(score, baseline)})"
  def format_verdict(:converged, score, baseline), do: "Converged (#{format_improvement(score, baseline)})"
  def format_verdict(:plateau, score, baseline), do: "Plateau reached (#{format_improvement(score, baseline)})"

  defp format_improvement(score, baseline) when baseline > 0 do
    pct = improvement(score, baseline) * 100
    :erlang.float_to_binary(pct, decimals: 2) <> "%"
  end

  defp format_improvement(_score, _baseline), do: "N/A"
end
