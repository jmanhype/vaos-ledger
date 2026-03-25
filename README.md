# VaosLedger

![Elixir](https://img.shields.io/badge/Elixir-1.17%2B-purple)
![OTP](https://img.shields.io/badge/OTP-27%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-208%20passing-brightgreen)

Epistemic governance framework for tracking claims, evidence, and attacks. A GenServer holds 14 entity maps in memory with atomic JSON file persistence. An Expected Information Gain (EIG) policy ranks 5 action types to decide what research to do next. An experiment loop iterates toward convergence using a 20% improvement threshold. A research pipeline runs idea-to-paper generation in 5 stages. All external intelligence (LLM calls, HTTP requests, code execution) is injected via callbacks -- the library has zero runtime coupling to any AI provider. 18 modules, 6,738 lines, 3 dependencies.

## Table of Contents

- [Architecture](#architecture)
- [How It Works](#how-it-works)
- [Expected Information Gain](#expected-information-gain)
- [Callback Injection](#callback-injection)
- [Data Model](#data-model)
- [Research Pipeline](#research-pipeline)
- [Design Decisions](#design-decisions)
- [Known Limitations](#known-limitations)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [References](#references)
- [License](#license)

## Architecture

```
VaosLedger.Supervisor (one_for_one)
└── Vaos.Ledger.Epistemic.Ledger   (GenServer, JSON persistence)
    ├── reads/writes ledger.json (atomic: tmp file + File.rename!)
    └── holds 14 entity maps in state
```

In test mode, the supervisor starts with no children -- each test creates its own Ledger instance for isolation.

**4 subsystems, 18 modules:**

| Subsystem | Modules | Lines | Role |
|-----------|---------|-------|------|
| Epistemic Core | Ledger, Models, Policy, Controller | 3,583 | Claim/evidence CRUD, EIG ranking, action decisions |
| Experiment Loop | Loop, Scorer, Verdict, Strategy | 916 | Iterative optimization with convergence detection |
| Research Pipeline | Pipeline, Literature, Paper, CodeExecutor | 1,270 | Idea-to-paper generation in 5 stages |
| ML Monitoring | Referee, Runner, CrashLearner | 788 | Trial monitoring, early stopping, crash pattern learning |

Two API facades delegate to subsystem modules:
- `VaosLedger` (`vaos_ledger.ex`, 114 lines) -- 65+ `defdelegate` calls, unified entry point
- `Vaos.Ledger` (`vaos/ledger.ex`, 44 lines) -- slim convenience facade

## How It Works

1. **Register claims** with novelty (0.0-1.0) and falsifiability (0.0-1.0) scores
2. **Attach evidence** with direction (`:support`, `:contradict`, `:inconclusive`) and strength
3. **Register attacks** against claims or assumptions with severity scores
4. **EIG policy** (`Policy.rank_actions/2`) generates up to 5 action proposals per non-archived claim, scored by weighted sum of uncertainty, novelty, falsifiability, and attack pressure
5. **Controller** (`Controller.decide/1`) picks the highest-EIG action, considering history to avoid repeating failed approaches
6. **Experiment loop** (`Loop`) executes the action, scores the result, checks for convergence (20% threshold), and evolves the strategy
7. **Research pipeline** (`Pipeline`) runs multi-stage generation: idea -> method -> literature -> experiments -> paper

After each mutation, the Ledger recalculates per-claim metrics including Bayesian confidence, belief/uncertainty scores, and derived status.

## Expected Information Gain

`Policy.rank_actions/2` generates `ActionProposal` structs scored as weighted sums clamped to [0.0, 1.0]. Priority thresholds: >= 0.75 = "now", >= 0.55 = "next", otherwise "watch".

**5 action types and their dominant weights:**

| Action | Primary Weight | Trigger Condition | Dominant Factor |
|--------|---------------|-------------------|-----------------|
| `:run_experiment` | 0.40 * uncertainty | Always generated | High uncertainty + novelty |
| `:challenge_assumption` | 0.50 * assumption_risk | Always generated | Risky assumptions |
| `:triage_attack` | 0.55 * attack_pressure | open_attack_count > 0 | Unresolved attacks |
| `:collect_counterevidence` | 0.40 * evidence_imbalance | evidence_count > 0 | Lopsided evidence |
| `:reproduce_result` | 0.45 * support_signal | support > 0.55, evidence <= 1 | Strong but thin support |

Each score also includes secondary terms (novelty, falsifiability, momentum, failure_pressure) with smaller weights. The `failure_pressure` composite is itself `0.45 * stagnation + 0.35 * crash_rate + 0.20 * low_yield` with branch-relief modifiers.

**Confidence update** (Bayesian posterior in `ledger.ex`):

```
prior_weight = 1.0 / (1.0 + evidence_count)
confidence = prior_weight * prior + (1.0 - prior_weight) * evidence_ratio
```

**Status derivation** from computed metrics:
- `:falsified` if contradict_score >= max(0.7, support_score * 1.25)
- `:supported` if support_score >= max(0.7, contradict_score * 1.5) AND open_attack_load < 0.25
- `:contested` if evidence/attacks exist with contradiction or open attacks
- `:active` if evidence exists without contradiction
- `:proposed` if no evidence and no attacks

## Callback Injection

The central design decision. Every external capability is injected as a function at call time. The library never imports an HTTP client, LLM SDK, or code runner.

**3 callback signatures:**

| Callback | Signature | Used By |
|----------|-----------|---------|
| `llm_fn` | `(String.t() -> {:ok, String.t()} \| {:error, term()})` | Pipeline, Scorer, Literature, CrashLearner |
| `http_fn` | `(String.t(), keyword() -> {:ok, map()} \| {:error, term()})` | Literature (Semantic Scholar, OpenAlex) |
| `code_fn` | `(String.t(), keyword() -> {:ok, %{stdout, stderr}} \| {:error, term()})` | CodeExecutor (sandboxed experiment execution) |

Additionally:
- `experiment_fn` -- `(map() -> {:ok, %{metrics: map()}} | {:error, term()})` used by Runner
- `fix_fn` -- `(code, error -> {:ok, new_code} | :give_up)` used by CodeExecutor for automatic code repair between retries

**Rationale:** Testable without network access. Every test provides stub callbacks returning canned responses. The host application chooses the LLM provider, manages API keys, and controls cost. The library has no opinion about which model or service is used.

**Tradeoff:** Callers must wire up callbacks at every entry point. There is no "just works" default configuration.

## Data Model

15 struct types defined in `epistemic/models.ex`. IDs are generated via `Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)`.

**Core entities:**

| Struct | ID Prefix | Key Fields |
|--------|-----------|------------|
| Claim | `claim_` | title, statement, novelty, falsifiability, confidence, status |
| Assumption | `assum_` | claim_id, text, rationale, risk (0.0-1.0) |
| Evidence | `evid_` | claim_id, direction, strength, confidence, source_type |
| Attack | `atk_` | claim_id, target_kind, target_id, severity, status, resolution |
| Artifact | `artif_` | claim_id, kind, title, content, source_path |

**Research entities:**

| Struct | ID Prefix | Key Fields |
|--------|-----------|------------|
| InputArtifact | `input_` | input_type, content, summary, linked_claim_ids |
| InnovationHypothesis | `hyp_` | statement, recommended_mode, overall_score, status |
| ProtocolDraft | `proto_` | hypothesis_id, eval_plan, baseline_plan, blockers |
| ArtifactTarget | `tgt_` | mode, target_type, mutable_fields, invariant_constraints |

**Evaluation entities:**

| Struct | ID Prefix | Key Fields |
|--------|-----------|------------|
| EvalSuite | `suite_` | scoring_method, aggregation, pass_threshold, cases |
| MutationCandidate | `cand_` | target_id, parent_candidate_id, review_status |
| EvalRun | `run_` | suite_id, candidate_id, score, passed, runtime_seconds |
| DecisionRecord | `dec_` | action_type, expected_information_gain, priority, reason |
| ExecutionRecord | `exec_` | decision_id, status, runtime_seconds, cost_estimate_usd |

The Claim struct maintains 14 ID-list fields linking to all child entity types. The Ledger holds 14 maps (one per entity type) keyed by entity ID.

## Research Pipeline

```
idea generation -> method development -> literature search -> experiments -> paper synthesis
         |                |                   |                  |               |
       llm_fn           llm_fn           http_fn + llm_fn    code_fn         llm_fn
```

**5 stages** executed sequentially via `with` in `Pipeline.run/1`:

| Stage | Module | Requires | Output |
|-------|--------|----------|--------|
| Idea | Pipeline | llm_fn | Research question + hypothesis |
| Method | Pipeline | llm_fn | Experimental methodology |
| Literature | Literature | http_fn | Ranked references (Semantic Scholar + OpenAlex) |
| Experiments | CodeExecutor | code_fn | Execution results + generated files |
| Paper | Paper | llm_fn | Section-by-section synthesis + LaTeX |

Literature ranking uses term-overlap scoring: title tokens weighted 3x, year bonus (2.0 for >= 2020, 1.0 for >= 2015), and log10 citation count bonus. Semantic Scholar is primary; OpenAlex is fallback.

CodeExecutor runs experiments via `Task.async` with 60s timeout, up to 3 retries. If `fix_fn` is provided, failed code is sent for automatic repair between retries. Generated files (png, jpg, pdf, svg, csv, json) are collected.

Paper module generates sections individually (title+abstract, introduction, methods, results, conclusions, keywords) and includes `to_latex/1` and `generate_bibliography/1` for academic output.

The pipeline supports iteration: if `iteration < max_iterations` and the paper is incomplete, all stages re-run.

## Design Decisions

**GenServer + JSON file persistence.** The Ledger holds all state in memory, serializing to a single JSON file on every mutation via atomic write (tmp file + `File.rename!`). Rationale: single-writer guarantees ordering without a database, JSON is human-readable for debugging, and the full state is always in memory for fast reads. Tradeoff: persistence I/O is on the critical path, and the file grows with entity count (not operation count, unlike append-only logs).

**EIG over random/FIFO action selection.** The Policy module scores actions by expected information gain rather than processing them in order. Rationale: focuses effort on the highest-uncertainty, highest-novelty claims first, avoiding wasted computation on settled questions. Tradeoff: the scoring weights are hand-tuned heuristics, not learned from data.

**Scorer heuristic over LLM scoring by default.** The `Scorer.estimate_score/2` function computes quality from status, runtime, and artifact metrics without an LLM call. `score_with_llm/4` is available but optional. Rationale: LLM scoring costs money and adds latency; the heuristic is free and fast. Tradeoff: heuristic quality is coarse (base score is 0.2/0.4/0.5/0.8 by status).

**Callback injection over module configuration.** Rather than `config :vaos_ledger, llm_module: MyLLM`, callbacks are passed as function arguments. Rationale: no global state, no Application env coupling, trivially testable with anonymous functions. Tradeoff: more verbose call sites.

**Schema versioning with corrupt-file backup.** On load failure, the corrupted file is copied to `{path}.corrupt.{timestamp}` before initializing fresh state. Schema version (currently 7) allows future migrations. Rationale: never silently lose data, always preserve the broken file for forensics.

## Known Limitations

- **Single-node JSON persistence** (`epistemic/ledger.ex`). No clustering, no concurrent writers. The JSON file is the only persistence mechanism -- no WAL, no replication.

- **Simplistic Scorer heuristic** (`experiment/scorer.ex`). The `estimate_score/2` function assigns base scores by status enum (`:succeeded` = 0.8, `:failed` = 0.2) and applies runtime/quality multipliers. Does not analyze actual output content without an LLM.

- **No claim graph visualization.** Claims, evidence, attacks, and assumptions form a rich graph, but no rendering or export (DOT, Mermaid, etc.) is provided.

- **Code execution needs external sandbox** (`research/code_executor.ex`). The `code_fn` callback must provide its own sandboxing. CodeExecutor wraps it in a `Task.async` with timeout, but the actual isolation (Docker, nsjail, etc.) is the caller's responsibility.

- **Term-overlap literature ranking** (`research/literature.ex`). Paper relevance is scored by token overlap between search query and paper title/abstract, not semantic similarity. This misses synonyms, abbreviations, and conceptual matches.

- **Hand-tuned EIG weights** (`epistemic/policy.ex`). The 5 action scoring formulas use fixed weights (e.g., 0.40 * uncertainty + 0.25 * novelty). These were set by inspection, not calibrated against experimental data.

- **Monotonically growing entity maps.** Entities are never garbage-collected from the in-memory maps. Archived claims remain in state. For long-running sessions with thousands of claims, memory usage grows without bound.

## Installation

As a path dependency (co-development):

```elixir
def deps do
  [
    {:vaos_ledger, path: "../vaos-ledger-build"}
  ]
end
```

Standalone:

```bash
git clone <repo-url> vaos-ledger-build
cd vaos-ledger-build
mix deps.get
mix test
```

Requires Elixir >= 1.17 and OTP >= 27.

## Usage

### Start the Ledger and Create Claims

```elixir
# Start a ledger instance (in production, started by the Application supervisor)
{:ok, pid} = Vaos.Ledger.Epistemic.Ledger.start_link(path: "/tmp/my_ledger.json")

# Create a claim
{:ok, claim} = Vaos.Ledger.Epistemic.Ledger.add_claim(pid,
  title: "Transformer attention scales quadratically",
  statement: "Self-attention in transformer models has O(n^2) time complexity",
  novelty: 0.3,
  falsifiability: 0.9
)
```

### Attach Evidence and Attacks

```elixir
# Add supporting evidence
{:ok, evidence} = Vaos.Ledger.Epistemic.Ledger.add_evidence(pid,
  claim_id: claim.id,
  summary: "Vaswani et al. (2017) Table 1 shows O(n^2 * d) complexity",
  direction: :support,
  strength: 0.9,
  confidence: 0.95,
  source_type: "paper",
  source_ref: "arxiv:1706.03762"
)

# Register an attack
{:ok, attack} = Vaos.Ledger.Epistemic.Ledger.add_attack(pid,
  claim_id: claim.id,
  description: "Linear attention variants (Katharopoulos 2020) achieve O(n) complexity",
  severity: 0.6
)
```

### Get Research Action Recommendations

```elixir
# Rank all possible actions by EIG
actions = Vaos.Ledger.Epistemic.Policy.rank_actions(pid)
# => [%ActionProposal{action_type: :triage_attack, expected_information_gain: 0.72, ...}, ...]

# Let the controller decide the next action
{:ok, decision} = Vaos.Ledger.Epistemic.Controller.decide(pid)
# => {:ok, %ControllerDecision{primary_action: %ActionProposal{...}, ...}}
```

### Run the Experiment Loop

```elixir
# Define callbacks
llm_fn = fn prompt -> MyLLM.complete(prompt) end
experiment_fn = fn config -> MyRunner.run(config) end

# Start the loop
{:ok, loop_pid} = Vaos.Ledger.Experiment.Loop.start_link(
  ledger: pid,
  llm_fn: llm_fn,
  experiment_fn: experiment_fn,
  max_iterations: 10
)

# Run to convergence
{:ok, result} = Vaos.Ledger.Experiment.Loop.run(loop_pid)
```

### Run the Research Pipeline

```elixir
llm_fn = fn prompt -> MyLLM.complete(prompt) end
http_fn = fn url, opts -> Req.get(url, opts) end
code_fn = fn code, opts -> Sandbox.execute(code, opts) end

{:ok, paper} = Vaos.Ledger.Research.Pipeline.run(
  topic: "Linear attention mechanisms",
  llm_fn: llm_fn,
  http_fn: http_fn,
  code_fn: code_fn
)
```

## Testing

```
$ mix test
........................................................................
........................................................................
................................................................
Finished in 14.8 seconds (0.9s async, 13.9s sync)
208 tests, 0 failures
```

16 test files, 2,866 lines. Tests use stub callbacks throughout -- no network calls, no LLM API keys required.

## Project Structure

```
lib/
  vaos_ledger.ex                                114 lines  Unified API facade (65+ defdelegate)
  vaos_ledger/application.ex                     23 lines  OTP Application supervisor
  vaos/ledger.ex                                 44 lines  Slim API facade
  vaos/ledger/
    epistemic/
      models.ex                                 289 lines  15 struct types + ID generation
      ledger.ex                               2,757 lines  GenServer: CRUD, JSON persistence, metrics
      policy.ex                                 276 lines  EIG action ranking (5 action types)
      controller.ex                             261 lines  Research action decision engine
    experiment/
      loop.ex                                   221 lines  Iterative optimization cycle
      scorer.ex                                 242 lines  Heuristic + LLM scoring with ETS cache
      verdict.ex                                106 lines  20% threshold convergence logic
      strategy.ex                               347 lines  Strategy.md read/write/evolve
    research/
      pipeline.ex                               648 lines  5-stage idea-to-paper pipeline
      literature.ex                             220 lines  Semantic Scholar + OpenAlex search
      paper.ex                                  265 lines  Section synthesis + LaTeX rendering
      code_executor.ex                          137 lines  Sandboxed execution with retry + fix_fn
    ml/
      referee.ex                                331 lines  Trial monitoring, kill losers, leaderboard
      runner.ex                                 282 lines  Experiment execution with checkpointing
      crash_learner.ex                          175 lines  Crash pattern learning + pitfall distillation
```

## References

- Dung, P. M. (1995). "On the Acceptability of Arguments and its Fundamental Role in Nonmonotonic Reasoning, Logic Programming and n-Person Games." *Artificial Intelligence*, 77(2), 321-357.
- Lindley, D. V. (1956). "On a Measure of the Information Provided by an Experiment." *The Annals of Mathematical Statistics*, 27(4), 986-1005.
- [Semantic Scholar API](https://api.semanticscholar.org/) -- Academic paper search and citation data
- [OpenAlex API](https://docs.openalex.org/) -- Open scholarly metadata

## License

MIT
