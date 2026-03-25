# vaos-ledger

Epistemic governance framework for AI agents. Claims, evidence, and attacks tracked in a GenServer with JSON persistence. Expected Information Gain (EIG) policy ranks actions by how much they reduce uncertainty. Experiment loop iterates candidates to convergence. Research pipeline generates ideas, methods, literature reviews, and papers. All external intelligence (LLM calls, HTTP requests, code execution) injected via callbacks.

19 modules, 7,631 lines of Elixir, 241 tests, 2 runtime dependencies (`jason`, `req`).

Part of the [VAOS](https://vaos.sh) agent infrastructure. The host application provides the LLM, the HTTP client, and the code sandbox. This library provides the epistemic structure.

| | |
|---|---|
| **Elixir** | >= 1.17 |
| **OTP** | >= 27 |
| **Tests** | 241, 0 failures |
| **Runtime deps** | 2 (`jason`, `req`) |
| **License** | MIT |

## Table of Contents

- [Architecture](#architecture)
- [How It Works](#how-it-works)
- [Expected Information Gain](#expected-information-gain)
- [Callback Injection](#callback-injection)
- [Data Model](#data-model)
- [Grounding](#grounding)
- [Research Pipeline](#research-pipeline)
- [Design Decisions](#design-decisions)
- [Known Limitations](#known-limitations)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [References](#references)

## Architecture

Five subsystems, each in its own namespace:

| Subsystem | Modules | Purpose |
|-----------|---------|---------|
| **Epistemic Core** | `ledger.ex` (2,852 lines), `models.ex`, `policy.ex`, `controller.ex`, `grounding.ex` | Claims, evidence, attacks, EIG scoring, decision making, execution grounding |
| **Experiment Loop** | `loop.ex`, `scorer.ex`, `strategy.ex`, `verdict.ex` | Iterate mutation candidates against eval suites until convergence |
| **Research Pipeline** | `pipeline.ex` (708 lines), `literature.ex`, `paper.ex`, `code_executor.ex` | Idea generation, literature search, method development, paper synthesis |
| **ML Monitoring** | `referee.ex`, `runner.ex`, `crash_learner.ex` | Experiment execution, failure analysis, hyperparameter adaptation |
| **Application** | `application.ex`, `vaos_ledger.ex`, `vaos/ledger.ex` | OTP supervision, public API facade |

```
VaosLedger.Supervisor (:one_for_one)
  |
  +-- Vaos.Ledger.Epistemic.Ledger (GenServer)
       |-- JSON persistence (ledger.json)
       |-- Claims, Evidence, Attacks, Artifacts
       |-- DecisionRecords, ExecutionRecords
       |-- InputArtifacts, Hypotheses, Protocols
       +-- Targets, EvalSuites, MutationCandidates, EvalRuns
```

Single GenServer, single JSON file. The Ledger holds all state. In test mode, the supervisor starts with zero children so each test creates its own isolated Ledger.

## How It Works

1. **Register claims** -- propositions the agent is evaluating. Each claim tracks its own evidence, assumptions, attacks, and decision history.
2. **Attach evidence** -- citations with direction (support/contradict/inconclusive), strength, confidence, and source metadata.
3. **Register attacks** -- evidence items that challenge other evidence or assumptions. Severity and resolution status tracked.
4. **EIG scoring** -- `Policy.rank_actions/2` generates scored action proposals for each claim. Actions ranked by expected information gain, not by likelihood of success.
5. **Controller decides** -- `Controller.decide/1` applies history feedback (penalizes repeated/failed actions, discounts one-shot completions), sorts by EIG, returns primary action + backlog.
6. **Experiment loop** -- for claims requiring empirical validation: define targets, eval suites, mutation candidates. Loop scores candidates against baselines until verdict (keep/discard/inconclusive).
7. **Research pipeline** -- for claims requiring literature support: generate ideas, develop methods, search literature, synthesize papers. Each stage uses `llm_fn` callback.

## Expected Information Gain

`Policy.rank_actions/2` generates up to 5 action types per claim, scored by weighted combinations of epistemic state:

| Action | Base Score Formula | Condition |
|--------|-------------------|-----------|
| `run_experiment` | `0.40*uncertainty + 0.25*novelty + 0.20*falsifiability + 0.15*attack_pressure` | Always |
| `challenge_assumption` | `0.50*highest_risk + 0.25*uncertainty + 0.15*novelty + 0.10*attack_pressure` | Claim has assumptions |
| `triage_attack` | `0.55*attack_pressure + 0.20*uncertainty + 0.15*falsifiability + 0.10*novelty` | Open attacks > 0 |
| `collect_counterevidence` | `0.40*evidence_imbalance + 0.25*novelty + 0.20*uncertainty + 0.15*falsifiability` | Evidence count > 0 |
| `reproduce_result` | `0.45*support_signal + 0.25*novelty + 0.20*falsifiability + 0.10*uncertainty` | Support > 0.55, evidence <= 1 |

Scores are modified by:
- **Failure pressure**: `0.45*stagnation + 0.35*crash_rate + 0.20*low_yield`, reduced by branch activity
- **Momentum**: `0.60*improvement + 0.25*frontier + 0.15*branch_activity`
- **History feedback** (in Controller): pending/running actions penalized 0.75x; failed actions penalized by runtime and cost pressure; completed one-shot actions penalized 0.35x

**Priority thresholds**: EIG >= 0.75 = "now", >= 0.55 = "next", else "watch".

The weights are heuristic, not learned. `collect_counterevidence` is deliberately scored against evidence imbalance because agents have a confirmation bias problem -- they find supporting evidence and stop looking. `challenge_assumption` requires an identified risky assumption because challenging unidentified assumptions produces noise.

## Callback Injection

The central design decision. No LLM provider, no HTTP client, no code executor is baked in. The host application passes functions:

| Callback | Signature | Used By |
|----------|-----------|---------|
| `llm_fn` | `String.t() -> {:ok, String.t()} \| {:error, term()}` | Pipeline, Scorer, Literature, CrashLearner |
| `http_fn` | `(String.t(), keyword()) -> {:ok, map()} \| {:error, term()}` | Literature (Semantic Scholar, OpenAlex) |
| `code_fn` | `(String.t(), keyword()) -> {:ok, %{stdout, stderr}} \| {:error, term()}` | CodeExecutor |
| `experiment_fn` | `map() -> {:ok, %{metrics: map()}} \| {:error, term()}` | Runner |
| `fix_fn` | `(code, error) -> {:ok, new_code} \| :give_up` | CodeExecutor (retry loop) |
| `adversary_fn` | `String.t() -> {:ok, String.t()} \| {:error, term()}` | Grounding (cheat interrogation) |

**Rationale**: Testable without network access -- tests pass `fn prompt -> {:ok, "mock response"} end`. Host picks LLM provider (OpenAI, Anthropic, local model). No API keys in the library. The tradeoff is verbosity at the call site: every function that touches external intelligence requires a callback argument.

## Data Model

17 struct types in `epistemic/models.ex`:

| Struct | ID Prefix | Key Fields |
|--------|-----------|------------|
| `Claim` | `claim_` | title, statement, status, novelty, falsifiability, confidence |
| `Assumption` | `assum_` | claim_id, text, rationale, risk |
| `Evidence` | `evid_` | claim_id, direction, strength, confidence, source_type, source_ref |
| `Attack` | `atk_` | claim_id, target_kind, target_id, severity, status, resolution |
| `Artifact` | `artif_` | claim_id, kind, title, content, source_type |
| `InputArtifact` | `input_` | title, input_type, content, summary |
| `InnovationHypothesis` | `hyp_` | input_id, statement, leverage, testability, novelty, overall_score |
| `ProtocolDraft` | `proto_` | hypothesis_id, recommended_mode, target_spec, eval_plan |
| `ArtifactTarget` | `tgt_` | claim_id, mode, target_type, mutable_fields, invariant_constraints |
| `EvalSuite` | `suite_` | target_id, scoring_method, aggregation, pass_threshold, cases |
| `MutationCandidate` | `cand_` | target_id, content, review_status |
| `EvalRun` | `run_` | candidate_id, suite_id, score, passed, runtime_seconds, cost_estimate_usd |
| `DecisionRecord` | `dec_` | claim_id, action_type, expected_information_gain, priority |
| `ExecutionRecord` | `exec_` | decision_id, status, runtime_seconds, cost_estimate_usd, artifact_quality |
| `ActionProposal` | -- | claim_id, action_type, EIG, priority, reason |
| `ControllerDecision` | -- | queue_state, primary_action, backlog |
| `Paper` | -- | title, abstract, methods, results, conclusions, bibliography |

All IDs are auto-generated UUIDs with type-prefixed strings. All timestamps are UTC ISO8601. Every struct has a `metadata: %{}` escape hatch for extension.

## Grounding

`Vaos.Ledger.Epistemic.Grounding` (720 lines). Derives evidence parameters from physical execution traces rather than trusting LLM self-assessment.

The problem: an LLM that generates a hypothesis AND grades its own execution will always report high confidence. Grounding removes the LLM from the self-grading loop.

**`from_execution/2`** -- pure function. Input: `%{stdout, stderr, exit_code, generated_files}`. Output: derived `direction`, `strength`, `confidence`, `summary`.

- Direction: exit_code 0 + assertion passes = `:support`; non-zero = `:contradict`; otherwise `:inconclusive`
- Strength: geometric mean of assertion_strength, output_substance, artifact_strength, error_penalty, code_substance
- Confidence: product of runtime_plausibility, stderr_noise, determinism

**`detect_cheat/3`** -- pure deterministic cheat detection. 7 checks:

| Check | What It Catches |
|-------|-----------------|
| Sleep inflation | `time.sleep`, `Thread.sleep`, busy loops |
| Assertion spam | >80% identical output lines |
| Fake artifacts | Raw bytes written to .png/.csv/.pdf |
| Hardcoded output | >50% of stdout lines found verbatim in source |
| Trivial computation | >70% of code lines are print statements |
| Compute inflation | Heavy numpy/scipy with results never used in output |
| Environment escape | Network access, subprocess, filesystem traversal |

**`interrogate/4`** -- sends code + execution trace to an adversary LLM. If `CHEAT_DETECTED` response, zeroes out strength and confidence. Recommended: proposer = cheap model (Haiku, GPT-4o-mini), adversary = reasoning model (o1, Claude Opus).

Security caveat per Rice's Theorem: no static analysis of a Turing-complete language can determine all runtime behaviors. The 7 checks catch common patterns, not all possible evasions.

## Research Pipeline

5-stage pipeline in `research/pipeline.ex` (708 lines):

```
Idea -> Method -> Literature -> Experiments -> Paper
```

Each stage takes the output of the previous stage plus an `llm_fn` callback:

1. **`generate_idea/2`** -- LLM generates a research idea from claim + evidence context
2. **`develop_method/2`** -- LLM develops experimental methodology from idea
3. **`literature.search/3`** -- Semantic Scholar API + OpenAlex API via `http_fn`. Extracts titles, abstracts, citation counts, DOIs
4. **`code_executor.run/3`** -- Execute experiment code via `code_fn` with retry loop using `fix_fn`
5. **`paper.synthesize/3`** -- LLM synthesizes paper with structured sections (abstract, introduction, methods, results, conclusions, bibliography)

`Literature.search/3` queries Semantic Scholar first (`api.semanticscholar.org/graph/v1/paper/search`), falls back to OpenAlex (`api.openalex.org/works`). Without a Semantic Scholar API key, retrieves ~5 papers per query instead of 15-20.

## Design Decisions

**Single GenServer + JSON file.** The Ledger is a single-writer append log. Writes are synchronous `File.write/3`. No concurrent write contention because there is only one process. Recovery is load-from-disk on start. Tradeoff: no distribution, no concurrent writes, file grows unbounded without external compaction. Adequate for single-agent workloads.

**EIG over random/FIFO action selection.** Random wastes compute on low-value actions. FIFO ignores evidence state changes. EIG directs agent effort toward the action most likely to reduce uncertainty. The weights are heuristic approximations, not optimal -- but they outperform random by directing counterevidence collection when evidence is imbalanced.

**Scorer heuristic over LLM scoring.** `experiment/scorer.ex` uses term overlap and structural heuristics to score experiment results. An LLM scorer would produce better quality scores but costs $0.01-0.10 per evaluation. With 50-100 evaluations per experiment loop, LLM scoring would cost $0.50-10.00 per claim. The heuristic is free and runs in microseconds.

**Callback injection over module configuration.** `Application.get_env(:vaos_ledger, :llm_module)` would be simpler at the call site. Callbacks were chosen because: (1) tests don't need mock modules or Application config manipulation, (2) the host can swap providers mid-session, (3) different pipeline stages can use different models (cheap for generation, expensive for adversarial review).

**Grounding over self-assessment.** Added after observing that LLM-generated experiments with LLM-graded results always converge to high scores. The Grounding module forces evidence through physical execution traces. This is the "adversarial by default" principle: treat all LLM output as potentially confabulated until grounded.

## Known Limitations

- **Single-node JSON persistence** (`epistemic/ledger.ex`): no replication, no distributed consensus. The JSON file is the only copy. If the file is corrupted or the disk fails, all state is lost.
- **Simplistic Scorer heuristic** (`experiment/scorer.ex`): evidence relevance scored by term overlap, not semantic similarity. A paper about "water memory" and a paper about "homeopathic dilutions" might not match even though they are directly related. Embedding-based similarity would improve this substantially.
- **No claim graph visualization.** Attack/support relationships exist in the data model but there is no way to render them. A D3.js force-directed graph or Graphviz export would make the epistemic state legible.
- **Code execution needs external sandbox** (`research/code_executor.ex`): the `code_fn` callback receives arbitrary code strings. The host must sandbox execution (Docker, Firecracker, nsjail). The library has no sandboxing built in.
- **Term-overlap ranking** (`research/literature.ex`): literature search results are ranked by keyword overlap, not semantic relevance. Related papers with different terminology are missed.
- **Research pipeline speed**: 15-20 minutes per full pipeline run (idea through paper). Not suitable for real-time applications.
- **Cheat detection is heuristic** (`epistemic/grounding.ex:detect_cheat/3`): 7 pattern-based checks. Catches common evasion strategies. Cannot catch all possible cheating per Rice's Theorem.

## Installation

As a path dependency:

```elixir
def deps do
  [
    {:vaos_ledger, path: "../vaos-ledger"}
  ]
end
```

Standalone:

```bash
git clone https://github.com/jmanhype/vaos-ledger.git
cd vaos-ledger
mix deps.get
mix test
```

## Usage

### Basic epistemic workflow

```elixir
# Start a Ledger (or let the Application supervisor start it)
{:ok, _pid} = VaosLedger.start_link(path: "my_ledger.json")

# Register a claim
:ok = VaosLedger.add_claim(%{
  title: "Homeopathy effectiveness",
  statement: "Homeopathic treatments are effective for chronic conditions",
  novelty: 0.3,
  falsifiability: 0.8
})

# Attach evidence
:ok = VaosLedger.add_evidence(%{
  claim_id: "claim_abc123",
  summary: "Cochrane systematic review finds no evidence beyond placebo",
  direction: :contradict,
  strength: 0.9,
  confidence: 0.85,
  source_type: "systematic_review",
  source_ref: "doi:10.1002/14651858.CD000567"
})

# Register an attack
:ok = VaosLedger.add_attack(%{
  claim_id: "claim_abc123",
  description: "The Cochrane review excluded 3 positive RCTs due to methodological concerns",
  target_kind: "evidence",
  target_id: "evid_def456",
  severity: 0.4,
  status: "open"
})

# Get the controller's recommendation
{:ok, decision} = VaosLedger.decide("claim_abc123")
# => %ControllerDecision{
#      primary_action: %ActionProposal{
#        action_type: :collect_counterevidence,
#        expected_information_gain: 0.72,
#        priority: "next",
#        reason: "Evidence imbalance detected..."
#      },
#      backlog: [...]
#    }
```

### Research pipeline

```elixir
llm_fn = fn prompt -> MyLLM.complete(prompt) end
http_fn = fn url, opts -> MyHTTP.get(url, opts) end

# Generate a research idea
{:ok, idea} = VaosLedger.generate_idea("claim_abc123", llm_fn: llm_fn)

# Develop methodology
{:ok, method} = VaosLedger.develop_method(idea, llm_fn: llm_fn)

# Synthesize paper
{:ok, paper} = VaosLedger.synthesize_paper(idea, method, llm_fn: llm_fn)
```

### Experiment loop

```elixir
# Define target, eval suite, mutation candidate, then run
scorer_fn = fn result -> VaosLedger.score_result(result) end
{:ok, verdict} = VaosLedger.meets_threshold?(score, 0.7)
```

## Testing

```
$ mix test
..........................................................................
..........................................................................
..........................................................................
.........................
241 tests, 0 failures
Finished in 16.9 seconds
```

Tests run in ~17 seconds. The slow tests are in the experiment loop and research pipeline modules which exercise multi-stage workflows with mock callbacks.

## Project Structure

```
vaos-ledger/
  lib/
    vaos_ledger.ex                        # Public API facade (65+ delegates)
    vaos_ledger/
      application.ex                      # OTP application, supervisor
    vaos/
      ledger.ex                           # Module namespace
      ledger/
        epistemic/
          controller.ex                   # EIG-based action selection
          grounding.ex                    # Execution trace grounding (720 lines)
          ledger.ex                       # GenServer, JSON persistence (2,852 lines)
          models.ex                       # 17 struct types
          policy.ex                       # EIG scoring weights
        experiment/
          loop.ex                         # Mutation candidate iteration
          scorer.ex                       # Heuristic result scoring
          strategy.ex                     # Hyperparameter adaptation
          verdict.ex                      # Keep/discard/inconclusive
        ml/
          crash_learner.ex                # Failure pattern analysis
          referee.ex                      # Experiment oversight
          runner.ex                       # Experiment execution
        research/
          code_executor.ex                # Sandboxed code execution + retry
          literature.ex                   # Semantic Scholar + OpenAlex
          paper.ex                        # Section synthesis
          pipeline.ex                     # 5-stage idea-to-paper (708 lines)
  test/
    16 test files, 241 tests
  mix.exs
```

## References

- Lindley, D.V. (1956). "On a Measure of the Information Provided by an Experiment." *Annals of Mathematical Statistics*, 27(4), 986-1005.
- Dung, P.M. (1995). "On the Acceptability of Arguments and its Fundamental Role in Nonmonotonic Reasoning, Logic Programming and n-Person Games." *Artificial Intelligence*, 77(2), 321-357.
- [Semantic Scholar API](https://api.semanticscholar.org/)
- [OpenAlex API](https://docs.openalex.org/)

## License

MIT
