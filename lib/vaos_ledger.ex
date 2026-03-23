defmodule VaosLedger do
  @moduledoc """
  Top-level API for Vaos.Ledger.

  Provides a unified interface to all ledger modules via defdelegate.
  """

  # Epistemic modules
  defdelegate start_link(opts), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate state(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate save(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_claims(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate claim_snapshot(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate summary_rows(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_claim(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_assumption(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_evidence(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_attack(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_artifact(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate register_input(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_hypothesis(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_protocol_draft(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate register_target(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate register_eval_suite(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate add_mutation_candidate(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate record_eval_run(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate promote_candidate(candidate_id, target_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate upsert_artifact(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate assumptions_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate evidence_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate attacks_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate artifacts_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate inputs_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate hypotheses_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate protocols_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate targets_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate eval_suites_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate mutation_candidates_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate eval_runs_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate decisions_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate executions_for_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate hypotheses_for_input(input_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate protocols_for_input(input_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate protocols_for_hypothesis(hypothesis_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_input(input_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_hypothesis(hypothesis_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_protocol(protocol_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_decision(decision_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_target(target_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_eval_suite(suite_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate get_mutation_candidate(candidate_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_decisions(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_executions(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_inputs(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_hypotheses(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate list_protocols(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate record_decision(proposal, opts), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate record_execution(attrs), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate link_hypothesis_to_claim(hypothesis_id, claim_id, status), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate link_input_to_claim(input_id, claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate link_protocol_to_claim(protocol_id, claim_id, status), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate refresh_all(), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate refresh_claim(claim_id), to: Vaos.Ledger.Epistemic.Ledger
  defdelegate claim_metrics(claim_id), to: Vaos.Ledger.Epistemic.Ledger

  # Controller
  defdelegate decide(ledger), to: Vaos.Ledger.Epistemic.Controller
  defdelegate decide(ledger, opts), to: Vaos.Ledger.Epistemic.Controller

  # Policy
  defdelegate rank_actions(ledger), to: Vaos.Ledger.Epistemic.Policy
  defdelegate rank_actions(ledger, opts), to: Vaos.Ledger.Epistemic.Policy

  # Experiment modules
  defdelegate meets_threshold?(best_score, baseline_score), to: Vaos.Ledger.Experiment.Verdict
  defdelegate keep_candidate?(candidate, best_score, baseline_score), to: Vaos.Ledger.Experiment.Verdict
  defdelegate improvement(score, baseline), to: Vaos.Ledger.Experiment.Verdict
  defdelegate format_verdict(verdict, score, baseline), to: Vaos.Ledger.Experiment.Verdict

  defdelegate score_result(result), to: Vaos.Ledger.Experiment.Scorer
  defdelegate score_result(result, opts), to: Vaos.Ledger.Experiment.Scorer
  defdelegate score_batch(results), to: Vaos.Ledger.Experiment.Scorer
  defdelegate score_batch(results, opts), to: Vaos.Ledger.Experiment.Scorer
  defdelegate compute_quality_score(metrics), to: Vaos.Ledger.Experiment.Scorer
  defdelegate estimate_score(execution_record, eval_runs), to: Vaos.Ledger.Experiment.Scorer

  defdelegate load(), to: Vaos.Ledger.Experiment.Strategy
  defdelegate load(path), to: Vaos.Ledger.Experiment.Strategy
  defdelegate save(strategy, path), to: Vaos.Ledger.Experiment.Strategy
  defdelegate evolve(strategy, metrics), to: Vaos.Ledger.Experiment.Strategy
  defdelegate get_hyperparameter(strategy, key), to: Vaos.Ledger.Experiment.Strategy
  defdelegate get_hyperparameter(strategy, key, default), to: Vaos.Ledger.Experiment.Strategy
  defdelegate set_hyperparameter(strategy, key, value), to: Vaos.Ledger.Experiment.Strategy
  defdelegate summary(strategy), to: Vaos.Ledger.Experiment.Strategy

  # Convenience aliases matching Vaos.Ledger API
  defdelegate load_strategy(), to: Vaos.Ledger.Experiment.Strategy, as: :load
  defdelegate load_strategy(path), to: Vaos.Ledger.Experiment.Strategy, as: :load
  defdelegate save_strategy(strategy), to: Vaos.Ledger.Experiment.Strategy, as: :save
  defdelegate save_strategy(strategy, path), to: Vaos.Ledger.Experiment.Strategy, as: :save
  defdelegate evolve_strategy(strategy, metrics), to: Vaos.Ledger.Experiment.Strategy, as: :evolve

  # Research modules
  defdelegate generate_idea(ledger, input_artifact), to: Vaos.Ledger.Research.Pipeline
  defdelegate develop_method(ledger, hypothesis), to: Vaos.Ledger.Research.Pipeline
  defdelegate synthesize_paper(ledger, results, hypothesis), to: Vaos.Ledger.Research.Pipeline

  @doc "Returns :world. Used for basic sanity testing."
  def hello, do: :world

  # ML modules
  defdelegate get_trial_stats(), to: Vaos.Ledger.ML.Referee
end
