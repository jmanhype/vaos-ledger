defmodule Vaos.Ledger.ML.Runner do
  @moduledoc """
  Executes experiment functions with time/step budgets and progress tracking.

  Port of ex_autoresearch Experiments.Runner, adapted for vaos-ledger:
  - No Axon/EXLA dependency -- accepts generic experiment_fn callbacks
  - Step-by-step metric tracking with configurable reporting
  - Checkpoint save/resume via serializable state
  - Time and step budget enforcement
  - Reports progress to a Referee via message passing

  All experiment logic is injected via experiment_fn callback:
    experiment_fn :: (config :: map() -> {:ok, %{metrics: map()}} | {:error, term()})
  """

  use GenServer
  require Logger

  defstruct [
    :trial_id,
    :experiment_fn,
    :config,
    :referee_pid,
    :max_seconds,
    :max_steps,
    :checkpoint_interval,
    :task_ref,
    status: :idle,
    current_step: 0,
    metrics_history: [],
    best_metrics: nil,
    checkpoint: nil,
    start_time: nil
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec run(GenServer.server()) :: :ok | {:error, :already_running}
  def run(server) do
    GenServer.call(server, :run)
  end

  @spec get_status(GenServer.server()) :: {:ok, map()}
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @spec get_checkpoint(GenServer.server()) :: {:ok, map() | nil}
  def get_checkpoint(server) do
    GenServer.call(server, :get_checkpoint)
  end

  @spec resume(GenServer.server(), map()) :: :ok | {:error, :already_running}
  def resume(server, checkpoint) do
    GenServer.call(server, {:resume, checkpoint})
  end

  @spec stop_experiment(GenServer.server()) :: :ok
  def stop_experiment(server) do
    GenServer.call(server, :stop_experiment)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      trial_id: Keyword.fetch!(opts, :trial_id),
      experiment_fn: Keyword.fetch!(opts, :experiment_fn),
      config: Keyword.get(opts, :config, %{}),
      referee_pid: Keyword.get(opts, :referee_pid),
      max_seconds: Keyword.get(opts, :max_seconds, 300),
      max_steps: Keyword.get(opts, :max_steps, 1000),
      checkpoint_interval: Keyword.get(opts, :checkpoint_interval, 100)
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call(:run, _from, state) do
    state = %{state | status: :running, start_time: System.monotonic_time(:millisecond)}
    notify_referee(state, {:trial_started, %{version_id: state.trial_id}})
    Process.send_after(self(), :check_time_budget, 1_000)
    send(self(), :run_next_step)
    {:reply, :ok, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      trial_id: state.trial_id,
      status: state.status,
      current_step: state.current_step,
      max_steps: state.max_steps,
      max_seconds: state.max_seconds,
      best_metrics: state.best_metrics,
      metrics_history_length: length(state.metrics_history),
      elapsed_seconds: elapsed_seconds(state)
    }
    {:reply, {:ok, status}, state}
  end

  def handle_call(:get_checkpoint, _from, state) do
    {:reply, {:ok, state.checkpoint}, state}
  end

  def handle_call({:resume, _checkpoint}, _from, %{status: :running} = state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call({:resume, checkpoint}, _from, state) do
    state = %{state |
      current_step: Map.get(checkpoint, :current_step, 0),
      metrics_history: Map.get(checkpoint, :metrics_history, []),
      best_metrics: Map.get(checkpoint, :best_metrics),
      config: Map.get(checkpoint, :config, state.config),
      status: :running,
      start_time: System.monotonic_time(:millisecond),
      checkpoint: checkpoint
    }
    notify_referee(state, {:trial_started, %{version_id: state.trial_id}})
    Process.send_after(self(), :check_time_budget, 1_000)
    send(self(), :run_next_step)
    {:reply, :ok, state}
  end

  def handle_call(:stop_experiment, _from, %{status: :running} = state) do
    state = finish(state, :stopped)
    {:reply, :ok, state}
  end

  def handle_call(:stop_experiment, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:run_next_step, %{status: status} = state) when status != :running do
    {:noreply, state}
  end

  def handle_info(:run_next_step, state) do
    if state.current_step >= state.max_steps do
      state = finish(state, :completed)
      {:noreply, state}
    else
      step_config = Map.merge(state.config, %{step: state.current_step})

      case safe_call(state.experiment_fn, step_config) do
        {:ok, %{metrics: metrics}} ->
          step = state.current_step + 1
          entry = %{step: step, metrics: metrics, timestamp: System.monotonic_time(:millisecond)}
          history = [entry | Enum.take(state.metrics_history, 999)]
          best = update_best_metrics(state.best_metrics, metrics)

          notify_referee(state, {:step, state.trial_id, step, metrics})

          checkpoint =
            if rem(step, state.checkpoint_interval) == 0 do
              %{
                current_step: step,
                metrics_history: history,
                best_metrics: best,
                config: state.config,
                trial_id: state.trial_id
              }
            else
              state.checkpoint
            end

          state = %{state |
            current_step: step,
            metrics_history: history,
            best_metrics: best,
            checkpoint: checkpoint
          }

          send(self(), :run_next_step)
          {:noreply, state}

        {:error, reason} ->
          Logger.error("Runner trial #{state.trial_id} step #{state.current_step} error: #{inspect(reason)}")
          state = finish(state, {:crashed, reason})
          {:noreply, state}

        other ->
          Logger.error("Runner trial #{state.trial_id} unexpected return: #{inspect(other)}")
          state = finish(state, {:crashed, {:unexpected_return, other}})
          {:noreply, state}
      end
    end
  end

  def handle_info(:check_time_budget, %{status: :running} = state) do
    elapsed = elapsed_seconds(state)
    if elapsed >= state.max_seconds do
      Logger.info("Runner trial #{state.trial_id} time budget exceeded")
      state = finish(state, :time_exceeded)
      {:noreply, state}
    else
      Process.send_after(self(), :check_time_budget, 1_000)
      {:noreply, state}
    end
  end

  def handle_info(:check_time_budget, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  defp safe_call(experiment_fn, config) do
    try do
      experiment_fn.(config)
    rescue
      e -> {:error, {Exception.message(e), Exception.format_stacktrace(__STACKTRACE__)}}
    end
  end

  defp finish(state, reason) do
    status =
      case reason do
        :completed -> :completed
        :stopped -> :stopped
        :time_exceeded -> :time_exceeded
        {:crashed, _} -> :crashed
        other -> other
      end

    checkpoint = %{
      current_step: state.current_step,
      metrics_history: state.metrics_history,
      best_metrics: state.best_metrics,
      config: state.config,
      trial_id: state.trial_id
    }

    case reason do
      {:crashed, error_detail} ->
        notify_referee(state, {:trial_crashed, %{
          version_id: state.trial_id,
          error: error_detail,
          step: state.current_step
        }})
      _ ->
        notify_referee(state, {:trial_completed, %{
          version_id: state.trial_id,
          status: status,
          step: state.current_step,
          best_metrics: state.best_metrics
        }})
    end

    %{state | status: status, checkpoint: checkpoint}
  end

  defp elapsed_seconds(%{start_time: nil}), do: 0.0
  defp elapsed_seconds(%{start_time: start}) do
    (System.monotonic_time(:millisecond) - start) / 1000.0
  end

  defp notify_referee(%{referee_pid: nil}, _msg), do: :ok
  defp notify_referee(%{referee_pid: pid}, msg) when is_pid(pid) do
    if Process.alive?(pid), do: send(pid, msg)
    :ok
  end
  defp notify_referee(_, _), do: :ok

  defp update_best_metrics(nil, metrics), do: metrics
  defp update_best_metrics(best, metrics) do
    best_loss = Map.get(best, :loss, Map.get(best, "loss"))
    new_loss = Map.get(metrics, :loss, Map.get(metrics, "loss"))
    cond do
      is_nil(new_loss) -> best
      is_nil(best_loss) -> metrics
      new_loss < best_loss -> metrics
      true -> best
    end
  end
end
