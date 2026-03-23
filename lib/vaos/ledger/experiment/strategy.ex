defmodule Vaos.Ledger.Experiment.Strategy do
  @moduledoc """
  Strategy.md read/write/evolve.
  Manages experimental strategy state.

  Port of strategy management from swarma.
  """

  @strategy_file "strategy.md"

  @type strategy :: %{
    name: String.t(),
    description: String.t(),
    goals: list(String.t()),
    constraints: list(String.t()),
    hyperparameters: map(),
    evolution_history: list(map())
  }

  @default_strategy %{
    name: "default",
    description: "Default experimental strategy",
    goals: [
      "Optimize for correctness",
      "Minimize runtime",
      "Maintain code quality"
    ],
    constraints: [
      "No breaking changes",
      "Follow coding standards",
      "Respect resource limits"
    ],
    hyperparameters: %{
      "learning_rate" => 0.01,
      "batch_size" => 32,
      "iterations" => 100
    },
    evolution_history: []
  }

  # Client API

  @doc """
  Load strategy from strategy.md file.
  """
  def load(path \\ ".") do
    strategy_path = Path.join(path, @strategy_file)

    if File.exists?(strategy_path) do
      parse_strategy(strategy_path)
    else
      {:ok, @default_strategy}
    end
  end

  @doc """
  Save strategy to strategy.md file.
  """
  def save(strategy, path \\ ".") do
    strategy_path = Path.join(path, @strategy_file)

    content = format_strategy(strategy)

    File.write!(strategy_path, content)

    {:ok, strategy_path}
  end

  @doc """
  Evolve strategy based on experiment results.
  """
  def evolve(strategy, metrics) do
    evolved =
      strategy
      |> update_hyperparameters(metrics)
      |> record_evolution(metrics)

    {:ok, evolved}
  end

  @doc """
  Get a hyperparameter value.
  """
  def get_hyperparameter(strategy, key, default \\ nil) do
    Map.get(strategy.hyperparameters, key, default)
  end

  @doc """
  Set a hyperparameter value.
  """
  def set_hyperparameter(strategy, key, value) do
    %{strategy |
      hyperparameters: Map.put(strategy.hyperparameters, key, value)
    }
  end

  @doc """
  Get strategy summary.
  """
  def summary(strategy) do
    """
    ## Strategy: #{strategy.name}

    #{strategy.description}

    ### Goals
    #{format_list(strategy.goals)}

    ### Constraints
    #{format_list(strategy.constraints)}

    ### Hyperparameters
    #{format_hyperparameters(strategy.hyperparameters)}

    ### Evolution History
    #{format_evolution_history(strategy.evolution_history)}
    """
  end

  # Private functions

  defp parse_strategy(path) do
    _content = File.read!(path)

    # Parse the markdown file
    # For now, return default strategy
    {:ok, @default_strategy}
  end

  defp format_strategy(strategy) do
    summary(strategy)
  end

  defp format_list(items) do
    items
    |> Enum.map(fn item -> "- #{item}" end)
    |> Enum.join("\n")
  end

  defp format_hyperparameters(hyperparams) do
    hyperparams
    |> Enum.map(fn {key, value} -> "- #{key}: #{format_value(value)}" end)
    |> Enum.join("\n")
  end

  defp format_value(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 4)
  end

  defp format_value(value) when is_binary(value) do
    value
  end

  defp format_value(value) when is_boolean(value) do
    if value, do: "true", else: "false"
  end

  defp format_value(value), do: inspect(value)

  defp format_evolution_history([]) do
    "No evolutions yet."
  end

  defp format_evolution_history(history) do
    history
    |> Enum.map(fn entry ->
      timestamp = Map.get(entry, :timestamp, "N/A")
      score = Map.get(entry, :best_score, "N/A")
      changes = Map.get(entry, :changes, %{})

      """
      - #{timestamp} (best: #{format_value(score)})
        #{format_changes(changes)}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_changes(changes) when changes == %{} do
    ""
  end

  defp format_changes(changes) do
    changes
    |> Enum.map(fn {key, {old, new}} ->
      "  - #{key}: #{format_value(old)} → #{format_value(new)}"
    end)
    |> Enum.join("\n")
  end

  defp update_hyperparameters(strategy, metrics) do
    # Use metrics to adjust hyperparameters
    # This is a simplified version - real implementation would be more sophisticated
    score = Map.get(metrics, :score, 0.5)
    runtime = Map.get(metrics, :runtime, 1.0)

    strategy
    |> adjust_learning_rate(score, runtime)
    |> adjust_batch_size(runtime)
  end

  defp adjust_learning_rate(strategy, score, runtime) do
    current = get_hyperparameter(strategy, "learning_rate", 0.01)

    new_rate =
      cond do
        score < 0.3 -> current * 0.8  # Lower LR if doing poorly
        score > 0.8 and runtime < 10.0 -> current * 1.2  # Increase LR if doing well and fast
        true -> current
      end

    set_hyperparameter(strategy, "learning_rate", new_rate)
  end

  defp adjust_batch_size(strategy, runtime) do
    current = get_hyperparameter(strategy, "batch_size", 32)

    new_size =
      cond do
        runtime < 5.0 -> min(current * 2, 128)  # Increase batch size if very fast
        runtime > 60.0 -> max(div(current, 2), 8)  # Decrease if slow
        true -> current
      end

    set_hyperparameter(strategy, "batch_size", new_size)
  end

  defp record_evolution(strategy, metrics) do
    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      best_score: Map.get(metrics, :best_score, 0.0),
      iteration: Map.get(metrics, :iteration, 0),
      changes: calculate_changes(strategy, metrics)
    }

    %{strategy |
      evolution_history: [entry | strategy.evolution_history]
    }
  end

  defp calculate_changes(_strategy, _metrics) do
    # Calculate what changed from previous state
    # For now, return empty map
    %{}
  end
end
