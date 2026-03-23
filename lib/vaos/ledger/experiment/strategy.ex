defmodule Vaos.Ledger.Experiment.Strategy do
  @moduledoc """
  Strategy.md read/write/evolve.
  Manages experimental strategy state.

  Port of strategy management from swarma.

  The strategy is persisted as a Markdown file (`strategy.md`) in a given
  directory.  When no file exists the default strategy is returned.  The
  `evolve/2` function adjusts hyperparameters based on observed metrics and
  appends an entry to the evolution history.
  """

  @strategy_file "strategy.md"

  @type t :: %{
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
  Load strategy from `strategy.md` in `path`.

  Returns the default strategy when no file exists.
  """
  @spec load(String.t()) :: {:ok, t()}
  def load(path \\ ".") do
    strategy_path = Path.join(path, @strategy_file)

    if File.exists?(strategy_path) do
      parse_strategy(strategy_path)
    else
      {:ok, @default_strategy}
    end
  end

  @doc """
  Save `strategy` to `strategy.md` in `path`.

  Returns `{:ok, absolute_path}`.
  """
  @spec save(t(), String.t()) :: {:ok, String.t()}
  def save(strategy, path \\ ".") do
    strategy_path = Path.join(path, @strategy_file)
    File.write!(strategy_path, format_strategy(strategy))
    {:ok, strategy_path}
  end

  @doc """
  Evolve `strategy` based on observed `metrics`.

  Adjusts hyperparameters (learning rate, batch size) and appends an entry
  to `:evolution_history`.  Returns `{:ok, evolved_strategy}`.
  """
  @spec evolve(t(), map()) :: {:ok, t()}
  def evolve(strategy, metrics) do
    evolved =
      strategy
      |> update_hyperparameters(metrics)
      |> record_evolution(metrics)

    {:ok, evolved}
  end

  @doc """
  Get the value of hyperparameter `key`, or `default` if absent.
  """
  @spec get_hyperparameter(t(), String.t(), term()) :: term()
  def get_hyperparameter(strategy, key, default \\ nil) do
    Map.get(strategy.hyperparameters, key, default)
  end

  @doc """
  Set hyperparameter `key` to `value`, returning the updated strategy.
  """
  @spec set_hyperparameter(t(), String.t(), term()) :: t()
  def set_hyperparameter(strategy, key, value) do
    %{strategy | hyperparameters: Map.put(strategy.hyperparameters, key, value)}
  end

  @doc """
  Return a Markdown summary of `strategy`.
  """
  @spec summary(t()) :: String.t()
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

  # Parses an existing strategy.md file.
  # Currently falls back to the default strategy while preserving the file
  # for human review; a future version may parse YAML front-matter.
  defp parse_strategy(path) do
    content = File.read!(path)

    # Attempt to extract a name from the first "## Strategy: <name>" heading.
    name =
      case Regex.run(~r/## Strategy:\s+(.+)/, content) do
        [_, captured] -> String.trim(captured)
        _ -> @default_strategy.name
      end

    {:ok, %{@default_strategy | name: name}}
  end

  defp format_strategy(strategy) do
    summary(strategy)
  end

  defp format_list(items) do
    Enum.map_join(items, "\n", fn item -> "- #{item}" end)
  end

  defp format_hyperparameters(hyperparams) do
    Enum.map_join(hyperparams, "\n", fn {key, value} -> "- #{key}: #{format_value(value)}" end)
  end

  defp format_value(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 4)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(value), do: inspect(value)

  defp format_evolution_history([]) do
    "No evolutions yet."
  end

  defp format_evolution_history(history) do
    Enum.map_join(history, "\n", fn entry ->
      timestamp = Map.get(entry, :timestamp, "N/A")
      score = Map.get(entry, :best_score, "N/A")
      changes = Map.get(entry, :changes, %{})

      """
      - #{timestamp} (best: #{format_value(score)})
        #{format_changes(changes)}
      """
    end)
  end

  defp format_changes(changes) when changes == %{}, do: ""

  defp format_changes(changes) do
    Enum.map_join(changes, "\n", fn {key, {old, new}} ->
      "  - #{key}: #{format_value(old)} → #{format_value(new)}"
    end)
  end

  defp update_hyperparameters(strategy, metrics) do
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
        score < 0.3 -> current * 0.8
        score > 0.8 and runtime < 10.0 -> current * 1.2
        true -> current
      end

    set_hyperparameter(strategy, "learning_rate", new_rate)
  end

  defp adjust_batch_size(strategy, runtime) do
    current = get_hyperparameter(strategy, "batch_size", 32)

    new_size =
      cond do
        runtime < 5.0 -> min(current * 2, 128)
        runtime > 60.0 -> max(div(current, 2), 8)
        true -> current
      end

    set_hyperparameter(strategy, "batch_size", new_size)
  end

  defp record_evolution(strategy, metrics) do
    old_hyperparams = @default_strategy.hyperparameters

    changes =
      strategy.hyperparameters
      |> Enum.reduce(%{}, fn {key, new_val}, acc ->
        old_val = Map.get(old_hyperparams, key)
        if old_val != nil and old_val != new_val do
          Map.put(acc, key, {old_val, new_val})
        else
          acc
        end
      end)

    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      best_score: Map.get(metrics, :best_score, 0.0),
      iteration: Map.get(metrics, :iteration, 0),
      changes: changes
    }

    %{strategy | evolution_history: [entry | strategy.evolution_history]}
  end
end
