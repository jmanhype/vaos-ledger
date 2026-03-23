defmodule Vaos.Ledger.Experiment.Loop do
  @moduledoc """
  Full swarma experiment cycle.
  Implements iterative experiment optimization loop.

  Port of swarma experiment loop.

  Each iteration: reads the current strategy, asks the controller for the
  next action, executes it, scores the result, checks the verdict, and
  updates the best score.  The loop stops when `max_iterations` is reached
  or `best_score` reaches 1.0.
  """

  use GenServer
  require Logger

  alias Vaos.Ledger.Epistemic.{Controller, Ledger}
  alias Vaos.Ledger.Experiment.{Scorer, Strategy, Verdict}

  defstruct [:ledger, :best_score, :iteration, :max_iterations, :threshold, :experiment_fn]

  # Client API

  @doc """
  Start the Loop GenServer.

  ## Options
    * `:max_iterations` — stop after this many iterations (default 100)
    * `:threshold` — improvement threshold passed to Verdict (default 0.2)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run the full swarma cycle on `ledger` and return the final loop state.

  ## Options
    * `:max_iterations` — override per-run max iterations
    * `:threshold` — override per-run improvement threshold
  """
  @spec run(GenServer.server(), keyword()) :: {:ok, map()}
  def run(ledger, opts \\ []) do
    GenServer.call(__MODULE__, {:run, ledger, opts}, :infinity)
  end

  @doc """
  Return current loop status (iteration, best_score, max_iterations, threshold).
  """
  @spec get_status() :: {:ok, map()}
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{
      ledger: nil,
      best_score: 0.0,
      iteration: 0,
      max_iterations: Keyword.get(opts, :max_iterations, 100),
      threshold: Keyword.get(opts, :threshold, 0.2),
      experiment_fn: Keyword.get(opts, :experiment_fn)
    }}
  end

  @impl true
  def handle_call({:run, ledger, opts}, _from, state) do
    max_iterations = Keyword.get(opts, :max_iterations, state.max_iterations)
    threshold = Keyword.get(opts, :threshold, state.threshold)

    Logger.info("Starting experiment loop with max_iterations=#{max_iterations}, threshold=#{threshold}")

    final_state = run_loop(%{state | ledger: ledger, max_iterations: max_iterations, threshold: threshold})

    {:reply, {:ok, final_state}, final_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      iteration: state.iteration,
      best_score: state.best_score,
      max_iterations: state.max_iterations,
      threshold: state.threshold
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(msg, _from, state) do
    Logger.warning("Loop received unexpected call: #{inspect(msg)}")
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Loop received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Loop logic

  defp run_loop(state) do
    if should_stop?(state) do
      Logger.info("Experiment loop completed at iteration #{state.iteration}")
      state
    else
      state = run_iteration(state)
      run_loop(state)
    end
  end

  defp should_stop?(state) do
    state.iteration >= state.max_iterations or
      state.best_score >= 1.0
  end

  defp run_iteration(state) do
    iteration = state.iteration + 1
    Logger.info("Running iteration #{iteration}")

    # 1. Read current strategy
    {:ok, strategy} = Strategy.load()

    # 2. Get next action from controller
    decision = Controller.decide(state.ledger)
    proposal = decision.primary_action

    # 3. Skip if no real claim to act on (bootstrap / no claims yet)
    if proposal.claim_id == "" do
      Logger.info("No active claim; skipping execution in iteration #{iteration}")
      %{state | iteration: iteration}
    else
      # 4. Execute the action
      execution = execute_action(proposal, state.ledger, state.experiment_fn)

      # 5. Score the result
      score = score_execution(execution, state.ledger)

      # 6. Apply verdict
      prev_best = state.best_score
      best_score = max(prev_best, score)
      baseline = if iteration == 1, do: 0.0, else: prev_best
      verdict = Verdict.verdict(best_score, prev_best, baseline, iteration, state.max_iterations, state.threshold)

      Logger.info("Iteration #{iteration}: score=#{score}, best=#{best_score}, verdict=#{verdict}")

      # 7. Evolve strategy based on metrics
      metrics = %{score: score, best_score: best_score, iteration: iteration, runtime: execution.runtime_seconds || 0.0}
      {:ok, _evolved} = Strategy.evolve(strategy, metrics)

      %{state | iteration: iteration, best_score: best_score}
    end
  end

  defp execute_action(proposal, _ledger, experiment_fn) do
    {status, notes, runtime} =
      if experiment_fn do
        try do
          case experiment_fn.(proposal) do
            {:ok, result} when is_map(result) ->
              {:succeeded, inspect(result), Map.get(result, :runtime_seconds, 1.0)}
            {:ok, result} ->
              {:succeeded, inspect(result), 1.0}
            {:error, reason} ->
              {:failed, "Experiment failed: " <> inspect(reason), 0.0}
          end
        rescue
          e ->
            Logger.error("Experiment function crashed: " <> Exception.message(e))
            {:failed, "Experiment crashed: " <> Exception.message(e), 0.0}
        end
      else
        Logger.warning("No experiment_fn provided; using stub execution for claim " <> proposal.claim_id)
        {:succeeded, "Executed in experiment loop (stub)", 1.0}
      end

    case Ledger.record_execution(
      claim_id: proposal.claim_id,
      claim_title: proposal.claim_title,
      action_type: proposal.action_type,
      executor: :manual,
      status: status,
      mode: proposal.mode || "experiment",
      notes: notes,
      runtime_seconds: runtime,
      cost_estimate_usd: 0.01
    ) do
      {:error, reason} ->
        Logger.warning("record_execution failed: #{inspect(reason)}, returning placeholder")
        %{claim_id: proposal.claim_id, status: :failed, notes: "", runtime_seconds: 0.0, artifact_quality: nil}

      record ->
        record
    end
  end

  defp score_execution(execution, _ledger) do
    eval_runs =
      if is_map(execution) and Map.has_key?(execution, :claim_id) and execution.claim_id != "" do
        Ledger.eval_runs_for_claim(execution.claim_id)
      else
        []
      end

    result = %{
      execution_record: execution,
      eval_runs: eval_runs,
      content: (if is_map(execution), do: Map.get(execution, :notes, ""), else: "")
    }

    {_status, score} = Scorer.score_result(result, fast: true)
    score
  end
end
