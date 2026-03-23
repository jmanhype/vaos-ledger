defmodule Vaos.Ledger.ML.CrashLearner do
  @moduledoc """
  Learns from experiment crashes and distills recurring patterns into pitfalls.

  Receives crash reports from failed trials, tracks frequency, and auto-distills
  patterns that occur 3+ times into pitfall summaries. Pitfalls are injected into
  system prompts so the LLM avoids known failure modes.

  Port of the crash-handling patterns from ex_autoresearch Researcher + Prompts
  (distill_pitfalls/1), extracted into a standalone GenServer.

  All external intelligence (LLM analysis) is via callbacks -- no direct deps.
  """

  use GenServer
  require Logger

  defstruct crashes: [], pitfalls: [], distill_threshold: 3

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec report_crash(GenServer.server(), String.t(), String.t(), String.t() | nil, map()) :: :ok
  def report_crash(server \\ __MODULE__, trial_id, error, stacktrace \\ nil, context \\ %{}) do
    GenServer.cast(server, {:crash, trial_id, error, stacktrace, context})
  end

  @spec get_pitfalls(GenServer.server()) :: {:ok, list(map())}
  def get_pitfalls(server \\ __MODULE__) do
    GenServer.call(server, :get_pitfalls)
  end

  @spec get_crashes(GenServer.server()) :: {:ok, list(map())}
  def get_crashes(server \\ __MODULE__) do
    GenServer.call(server, :get_crashes)
  end

  @spec analyze_crash(GenServer.server(), String.t(), map(), function()) ::
          {:ok, String.t()} | {:error, term()}
  def analyze_crash(server \\ __MODULE__, error, context, llm_fn) do
    GenServer.call(server, {:analyze_crash, error, context, llm_fn}, :timer.seconds(60))
  end

  @spec distill_pitfalls(GenServer.server(), function()) :: {:ok, list(map())} | {:error, term()}
  def distill_pitfalls(server \\ __MODULE__, llm_fn) do
    GenServer.call(server, {:distill_pitfalls, llm_fn}, :timer.seconds(60))
  end

  @impl true
  def init(opts) do
    threshold = Keyword.get(opts, :distill_threshold, 3)
    {:ok, %__MODULE__{distill_threshold: threshold}}
  end

  @impl true
  def handle_cast({:crash, trial_id, error, stacktrace, context}, state) do
    crash = %{
      trial_id: trial_id,
      error: error,
      stacktrace: stacktrace,
      context: context,
      timestamp: System.system_time(:second)
    }

    crashes = [crash | state.crashes]
    state = %{state | crashes: crashes}
    state = maybe_auto_distill(state)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_pitfalls, _from, state) do
    {:reply, {:ok, state.pitfalls}, state}
  end

  @impl true
  def handle_call(:get_crashes, _from, state) do
    {:reply, {:ok, state.crashes}, state}
  end

  @impl true
  def handle_call({:analyze_crash, error, context, llm_fn}, _from, state) do
    enriched_context = Map.put(context, :known_pitfalls, state.pitfalls)

    result =
      try do
        llm_fn.(error, enriched_context)
      rescue
        e -> {:error, Exception.message(e)}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:distill_pitfalls, llm_fn}, _from, state) do
    case try_distill(state.crashes, llm_fn) do
      {:ok, new_pitfalls} ->
        merged = merge_pitfalls(state.pitfalls, new_pitfalls)
        {:reply, {:ok, merged}, %{state | pitfalls: merged}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  defp maybe_auto_distill(state) do
    frequencies =
      state.crashes
      |> Enum.group_by(&error_signature/1)
      |> Enum.map(fn {sig, crashes} -> {sig, length(crashes), hd(crashes).error} end)
      |> Enum.filter(fn {_sig, count, _error} -> count >= state.distill_threshold end)

    new_pitfalls =
      frequencies
      |> Enum.map(fn {sig, count, error} ->
        %{
          pattern: sig,
          count: count,
          summary: "Recurring crash (#{count}x): #{String.slice(error, 0, 200)}"
        }
      end)

    merged = merge_pitfalls(state.pitfalls, new_pitfalls)
    %{state | pitfalls: merged}
  end

  defp error_signature(%{error: error}) when is_binary(error) do
    error
    |> String.replace(~r/#PID<[^>]+>/, "#PID<...>")
    |> String.replace(~r/#Reference<[^>]+>/, "#Ref<...>")
    |> String.replace(~r/\d+/, "N")
    |> String.slice(0, 150)
  end

  defp error_signature(_), do: "unknown"

  defp try_distill(crashes, llm_fn) do
    try do
      llm_fn.(crashes)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp merge_pitfalls(existing, new_pitfalls) do
    # Merge by keeping the one with higher count (preserves both counts correctly)
    existing_map = Map.new(existing, fn p -> {p.pattern, p} end)

    merged =
      Enum.reduce(new_pitfalls, existing_map, fn new_p, acc ->
        case Map.get(acc, new_p.pattern) do
          nil ->
            Map.put(acc, new_p.pattern, new_p)

          old ->
            # Keep the entry with the higher count; on tie, prefer the newer summary
            merged_entry =
              if old.count >= new_p.count do
                %{old | count: old.count}
              else
                %{new_p | count: new_p.count}
              end

            Map.put(acc, new_p.pattern, merged_entry)
        end
      end)

    Map.values(merged)
  end
end
