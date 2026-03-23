defmodule Vaos.Ledger do
  @moduledoc """
  Top-level API for Vaos.Ledger.
  """

  alias Vaos.Ledger.Epistemic
  alias Vaos.Ledger.Experiment
  alias Vaos.Ledger.Research
  alias Vaos.Ledger.ML

  # Epistemic Ledger
  defdelegate start_link(opts), to: Epistemic.Ledger
  defdelegate state(), to: Epistemic.Ledger
  defdelegate save(), to: Epistemic.Ledger
  defdelegate add_claim(attrs), to: Epistemic.Ledger
  defdelegate add_evidence(attrs), to: Epistemic.Ledger
  defdelegate add_attack(attrs), to: Epistemic.Ledger
  defdelegate add_assumption(attrs), to: Epistemic.Ledger
  defdelegate list_claims(), to: Epistemic.Ledger
  defdelegate get_claim(id), to: Epistemic.Ledger
  defdelegate refresh_all(), to: Epistemic.Ledger
  defdelegate refresh_claim(id), to: Epistemic.Ledger
  defdelegate summary_rows(), to: Epistemic.Ledger

  # Controller
  defdelegate decide(ledger_state), to: Epistemic.Controller

  # Policy
  defdelegate rank_actions(claims), to: Epistemic.Policy
  defdelegate rank_actions(claims, opts), to: Epistemic.Policy

  # Experiment
  defdelegate score_result(output), to: Experiment.Scorer
  defdelegate load_strategy(), to: Experiment.Strategy, as: :load
  defdelegate save_strategy(strategy), to: Experiment.Strategy, as: :save
  defdelegate evolve_strategy(strategy, learnings), to: Experiment.Strategy, as: :evolve

  # Research
  defdelegate run_research(), to: Research.Pipeline, as: :run
  defdelegate run_research(opts), to: Research.Pipeline, as: :run

  # ML
  defdelegate start_referee(opts), to: ML.Referee, as: :start_link
end
