defmodule Vaos.Ledger.ML.Referee do
  @moduledoc """
  Monitor trials and kill losers. Subscribes to trial events and compares progress.

  Port of ex_autoresearch Agent.Referee with enhancements:
  - Early stop detection: stops trial if improvement < threshold for N consecutive steps
  - Trial migration: move a winning trial config to a new runner
  - CrashLearner integration: forwards crashes for pattern learning
  - Leaderboard: sorted view of all trials by best score
  """

  use GenServer
  require Logger

  defstruct [:step_budget, :trials, :killed, :crash_learner_pid,
             :early_stop_patience, :early_stop_threshold]

  # Client API

  @doc """
  Start the Referee GenServer.

  ## Options
    * `:step_budget` -- total step budget (required)
    * `:crash_learner_pid` -- PID of CrashLearner to forward crashes to
    * `:early_stop_patience` -- steps without improvement before early stop (default: 10)
    * `:early_stop_threshold` -- minimum improvement to count as progress (default: 0.001)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_status() :: {:ok, map()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @spec get_trial_stats() :: {:ok, list(map())}
  def get_trial_stats do
    GenServer.call(__MODULE__, :get_trial_stats)
  end

  @doc "Return trials sorted by best score (descending)."
  @spec get_leaderboard() :: {:ok, list(map())}
  def get_leaderboard do
    GenServer.call(__MODULE__, :get_leaderboard)
  end

  @doc "Migrate a winning trial's config to a new runner."
  @spec migrate_trial(String.t(), pid()) :: {:ok, map()} | {:error, :not_found}
  def migrate_trial(version_id, new_runner_pid) do
    GenServer.call(__MODULE__, {:migrate_trial, version_id, new_runner_pid})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    step_budget = Keyword.fetch!(opts, :step_budget)
    crash_learner_pid = Keyword.get(opts, :crash_learner_pid)
    early_stop_patience = Keyword.get(opts, :early_stop_patience, 10)
    early_stop_threshold = Keyword.get(opts, :early_stop_threshold, 0.001)

    {:ok, %__MODULE__{
      step_budget: step_budget,
      trials: %{},
      killed: MapSet.new(),
      crash_learner_pid: crash_learner_pid,
      early_stop_patience: early_stop_patience,
      early_stop_threshold: early_stop_threshold
    }}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      step_budget: state.step_budget,
      trial_count: map_size(state.trials),
      killed_count: MapSet.size(state.killed)
    }
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:get_trial_stats, _from, state) do
    stats =
      state.trials
      |> Enum.map(fn {vid, trial} ->
        %{
          version_id: vid,
          current_step: length(trial.points),
          best_score: trial.best_score,
          status: trial.status,
          killed: MapSet.member?(state.killed, vid)
        }
      end)
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:get_leaderboard, _from, state) do
    leaderboard =
      state.trials
      |> Enum.map(fn {vid, trial} ->
        %{
          version_id: vid,
          current_step: length(trial.points),
          best_score: trial.best_score,
          status: trial.status,
          killed: MapSet.member?(state.killed, vid),
          stale_steps: Map.get(trial, :stale_steps, 0)
        }
      end)
      |> Enum.sort_by(fn t -> t.best_score end, :desc)
    {:reply, {:ok, leaderboard}, state}
  end

  @impl true
  def handle_call({:migrate_trial, version_id, new_runner_pid}, _from, state) do
    case Map.get(state.trials, version_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      trial ->
        migration_data = %{
          version_id: version_id,
          best_score: trial.best_score,
          points: trial.points,
          config: Map.get(trial, :config, %{}),
          migrated_to: new_runner_pid
        }
        updated_trial = Map.put(trial, :status, :migrated)
        new_state = %{state | trials: Map.put(state.trials, version_id, updated_trial)}
        {:reply, {:ok, migration_data}, new_state}
    end
  end

  def handle_call(msg, _from, state) do
    Logger.warning("Referee received unexpected call: #{inspect(msg)}")
    {:reply, {:error, :unknown_call}, state}
  end

  # Event handling via handle_info

  @impl true
  def handle_info({:trial_started, %{version_id: vid}}, state) do
    Logger.info("Trial started: #{vid}")
    new_state = %{state |
      trials: Map.put(state.trials, vid, %{
        points: [], best_score: 0.0, status: :running,
        stale_steps: 0, last_best: 0.0, config: %{}
      })
    }
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:trial_completed, %{version_id: vid}}, state) do
    Logger.info("Trial completed: #{vid}")
    new_state = %{state |
      trials: Map.delete(state.trials, vid),
      killed: MapSet.delete(state.killed, vid)
    }
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:step, %{version_id: vid, step: step, loss: loss}}, state) do
    if MapSet.member?(state.killed, vid) do
      {:noreply, state}
    else
      Logger.debug("Step update: #{vid}, step=#{step}, loss=#{loss}")
      state = update_trial(state, vid, step, loss)
      state = check_early_stop(state, vid)
      state = maybe_kill_loser(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:trial_killed, %{version_id: vid}}, state) do
    Logger.info("Trial killed: #{vid}")
    new_state = %{state | killed: MapSet.put(state.killed, vid)}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:trial_crashed, %{version_id: vid, error: error} = info}, state) do
    Logger.error("Trial crashed: #{vid} -- #{inspect(error)}")

    if state.crash_learner_pid && Process.alive?(state.crash_learner_pid) do
      step = Map.get(info, :step, 0)
      Vaos.Ledger.ML.CrashLearner.report_crash(
        state.crash_learner_pid, vid, inspect(error), nil, %{step: step}
      )
    end

    new_state = %{state |
      trials: Map.delete(state.trials, vid),
      killed: MapSet.delete(state.killed, vid)
    }
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Referee received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Trial management

  defp update_trial(state, vid, step, loss) do
    trial = Map.get(state.trials, vid, %{
      points: [], best_score: -1.0, status: :running,
      stale_steps: 0, last_best: -1.0, config: %{}
    })
    points = [{step, loss} | Enum.take(trial.points, 99)]
    new_score = 1.0 - loss
    best_score = max(trial.best_score, new_score)

    last_best = Map.get(trial, :last_best, -1.0)
    stale_steps =
      if best_score > last_best + state.early_stop_threshold do
        0
      else
        Map.get(trial, :stale_steps, 0) + 1
      end

    updated_trial = %{
      points: points,
      best_score: best_score,
      status: :running,
      stale_steps: stale_steps,
      last_best: best_score,
      config: Map.get(trial, :config, %{})
    }

    %{state | trials: Map.put(state.trials, vid, updated_trial)}
  end

  defp check_early_stop(state, vid) do
    case Map.get(state.trials, vid) do
      nil -> state
      trial ->
        if trial.stale_steps >= state.early_stop_patience do
          Logger.info("Early stopping trial #{vid}: no improvement for #{trial.stale_steps} steps")
          kill_trial(state, vid)
        else
          state
        end
    end
  end

  defp maybe_kill_loser(state) do
    trials_with_points =
      state.trials
      |> Enum.filter(fn {_vid, trial} -> length(trial.points) > 0 end)

    if length(trials_with_points) >= 2 do
      kill_worst(state, trials_with_points)
    else
      state
    end
  end

  defp kill_worst(state, trials) do
    checkpoint = div(state.step_budget, 2)

    at_checkpoint =
      Enum.filter(trials, fn {_vid, trial} -> length(trial.points) >= checkpoint end)

    if length(at_checkpoint) >= 2 do
      sorted =
        at_checkpoint
        |> Enum.map(fn {vid, trial} -> {vid, checkpoint_score(trial, checkpoint)} end)
        |> Enum.sort_by(fn {_vid, score} -> score end, :asc)

      case sorted do
        [{worst_vid, worst_score}, {_best_vid, best_score} | _] ->
          if best_score > 0 and worst_score < best_score * 0.8 do
            Logger.info("Killing trial #{worst_vid}: score #{worst_score} vs best #{best_score}")
            kill_trial(state, worst_vid)
          else
            state
          end
        _ -> state
      end
    else
      state
    end
  end

  defp checkpoint_score(trial, checkpoint) do
    case Enum.find(trial.points, fn {step, _loss} -> step == checkpoint end) do
      nil ->
        case trial.points do
          [{_step, loss} | _] -> 1.0 - loss
          _ -> trial.best_score
        end
      {_step, loss} -> 1.0 - loss
    end
  end

  defp kill_trial(state, vid) do
    %{state | killed: MapSet.put(state.killed, vid)}
  end
end
