defmodule Vaos.Ledger.Experiment.Loop do
  @moduledoc """
  Full swarma experiment cycle.
  Implements iterative experiment optimization loop.

  Port of swarma experiment loop.
  """

  use GenServer
  require Logger

  alias Vaos.Ledger.Epistemic.Ledger
  alias Vaos.Ledger.Experiment.Scorer

  defstruct [:ledger, :best_score, :iteration, :max_iterations, :threshold]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run(ledger, opts \\ []) do
    GenServer.call(__MODULE__, {:run, ledger, opts})
  end

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
      threshold: Keyword.get(opts, :threshold, 0.2)
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

    # Get pending actions from controller
    decision = get_next_action(state.ledger)

    # Execute action
    execution = execute_action(decision, state.ledger)

    # Score results
    score = score_execution(execution, state.ledger)

    # Update best score
    best_score = max(state.best_score, score)

    Logger.info("Iteration #{iteration} complete: score=#{score}, best=#{best_score}")

    %{state |
      iteration: iteration,
      best_score: best_score
    }
  end

  defp get_next_action(_ledger) do
    # Use controller to decide next action
    # For now, return a placeholder
    %{
      claim_id: "",
      claim_title: "experiment",
      action_type: :run_experiment,
      priority: "now"
    }
  end

  defp execute_action(decision, _ledger) do
    # Execute the action
    # For now, create a placeholder execution record
    {:ok, execution} =
      Ledger.record_execution(
        claim_id: decision.claim_id,
        claim_title: decision.claim_title,
        action_type: decision.action_type,
        executor: :manual,
        status: :succeeded,
        mode: "experiment",
        notes: "Executed in experiment loop",
        runtime_seconds: 1.0,
        cost_estimate_usd: 0.01
      )

    execution
  end

  defp score_execution(execution, _ledger) do
    # Get eval runs for this execution
    eval_runs = Ledger.eval_runs_for_claim(execution.claim_id)

    # Use scorer to evaluate
    result = %{
      execution_record: execution,
      eval_runs: eval_runs,
      content: execution.notes || ""
    }

    {_status, score} = Scorer.score_result(result, fast: true)

    score
  end
end
