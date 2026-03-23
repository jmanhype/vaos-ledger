defmodule Vaos.Ledger.ML.Referee do
  @moduledoc """
  Monitor trials and kill losers.
  Subscribes to trial events and compares progress.

  Port of ex_autoresearch Agent.Referee.

  In a real deployment the Referee would subscribe to a PubSub topic such as
  `"agent:events"` and receive `{:trial_started, _}`, `{:step, _}`, etc.
  messages from worker processes.  In the current implementation the caller
  sends those messages directly (`send(Referee, …)`), which is the interface
  exercised by the tests.

  Kill logic: whenever a step update arrives, `maybe_kill_loser/1` inspects
  all trials that have reached `div(step_budget, 2)` steps.  If the worst
  performer is more than 20 % below the best performer it is marked as killed
  in the `:killed` MapSet (and, in a real system, a kill signal would be sent
  to the trial worker).
  """

  use GenServer
  require Logger

  defstruct [:step_budget, :trials, :killed]

  # Client API

  @doc """
  Start the Referee GenServer.

  ## Required options
    * `:step_budget` — total step budget; halfway point is used as the kill
      checkpoint.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return a summary status map: step_budget, trial_count, killed_count.
  """
  @spec get_status() :: {:ok, map()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Return per-trial stats: version_id, current_step, best_score, status, killed.
  """
  @spec get_trial_stats() :: {:ok, list(map())}
  def get_trial_stats do
    GenServer.call(__MODULE__, :get_trial_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    step_budget = Keyword.fetch!(opts, :step_budget)

    # In a real implementation, subscribe to PubSub:
    # Phoenix.PubSub.subscribe(Referee.PubSub, "agent:events")

    {:ok, %__MODULE__{
      step_budget: step_budget,
      trials: %{},
      killed: MapSet.new()
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
  def handle_call(msg, _from, state) do
    Logger.warning("Referee received unexpected call: #{inspect(msg)}")
    {:reply, {:error, :unknown_call}, state}
  end

  # Event handling via handle_info (PubSub / direct send)

  @impl true
  def handle_info({:trial_started, %{version_id: vid}}, state) do
    Logger.info("Trial started: #{vid}")

    new_state = %{state |
      trials: Map.put(state.trials, vid, %{points: [], best_score: 0.0, status: :running})
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
    # Ignore events from already-killed trials
    if MapSet.member?(state.killed, vid) do
      {:noreply, state}
    else
      Logger.debug("Step update: #{vid}, step=#{step}, loss=#{loss}")

      state = update_trial(state, vid, step, loss)
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
  def handle_info(msg, state) do
    Logger.warning("Referee received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Trial management

  defp update_trial(state, vid, step, loss) do
    trial = Map.get(state.trials, vid, %{points: [], best_score: -1.0, status: :running})
    points = [{step, loss} | Enum.take(trial.points, 99)]
    best_score = max(trial.best_score, 1.0 - loss)

    %{state | trials: Map.put(state.trials, vid, %{
      points: points,
      best_score: best_score,
      status: :running
    })}
  end

  defp maybe_kill_loser(state) do
    trials_with_points =
      state.trials
      |> Enum.filter(fn {_vid, trial} ->
        length(trial.points) > 0
      end)

    if length(trials_with_points) >= 2 do
      kill_worst(state, trials_with_points)
    else
      state
    end
  end

  defp kill_worst(state, trials) do
    checkpoint = div(state.step_budget, 2)

    # Find trials that have reached checkpoint
    at_checkpoint =
      Enum.filter(trials, fn {_vid, trial} ->
        length(trial.points) >= checkpoint
      end)

    if length(at_checkpoint) >= 2 do
      # Compare scores at checkpoint
      sorted =
        at_checkpoint
        |> Enum.map(fn {vid, trial} ->
          {vid, checkpoint_score(trial, checkpoint)}
        end)
        |> Enum.sort_by(fn {_vid, score} -> score end, :asc)

      # Kill worst if >20% worse than best
      case sorted do
        [{worst_vid, worst_score}, {_best_vid, best_score} | _] ->
          if best_score > 0 and worst_score < best_score * 0.8 do
            Logger.info("Killing trial #{worst_vid}: score #{worst_score} vs best #{best_score}")
            kill_trial(state, worst_vid)
          else
            state
          end

        _ ->
          state
      end
    else
      state
    end
  end

  defp checkpoint_score(trial, checkpoint) do
    case Enum.find(trial.points, fn {step, _loss} -> step == checkpoint end) do
      nil ->
        # Use the most recent point if checkpoint step not found exactly
        case trial.points do
          [{_step, loss} | _] -> 1.0 - loss
          _ -> trial.best_score
        end

      {_step, loss} ->
        1.0 - loss
    end
  end

  defp kill_trial(state, vid) do
    # In a real implementation, send a kill signal to the trial worker process.
    # Here we mark the trial in the killed set; the next step event for this
    # vid will be silently ignored (see handle_info for :step above).
    %{state | killed: MapSet.put(state.killed, vid)}
  end
end
