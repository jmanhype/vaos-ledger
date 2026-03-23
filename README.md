# Vaos Ledger

An Elixir project for epistemic governance and auto-research engine.

## Build Status

This project has been built according to the 13-step specification:

✓ Step 1: Vaos.Ledger.Epistemic.Models - All structs ported from AIEQ-Core
✓ Step 2: Vaos.Ledger.Epistemic.Ledger - GenServer with JSON persistence
✓ Step 3: Vaos.Ledger.Epistemic.Policy - Expected information gain ranking
✓ Step 4: Vaos.Ledger.Epistemic.Controller - Decides next action
✓ Step 5: Vaos.Ledger.Experiment.Verdict - >20% threshold logic
✓ Step 6: Vaos.Ledger.Experiment.Scorer - Cheap LLM scoring
✓ Step 7: Vaos.Ledger.Experiment.Loop - Full swarma cycle
✓ Step 8: Vaos.Ledger.Experiment.Strategy - Strategy.md read/write/evolve
✓ Step 9: Vaos.Ledger.Research.Pipeline - idea → method → results → paper
✓ Step 10: Vaos.Ledger.ML.Referee - Monitor trials, kill losers
✓ Step 11: Tests for core modules
✓ Step 12: Vaos.Ledger top-level API with defdelegate
✓ Step 13: Vaos.Ledger.Application - OTP supervisor

## Architecture

### Core Modules

- `Vaos.Ledger.Epistemic.Models` - Data structures (Claim, Evidence, Attack, etc.)
- `Vaos.Ledger.Epistemic.Ledger` - GenServer with JSON persistence
- `Vaos.Ledger.Epistemic.Policy` - Information gain ranking
- `Vaos.Ledger.Epistemic.Controller` - Research controller

### Experiment Modules

- `Vaos.Ledger.Experiment.Verdict` - Threshold-based verdict logic
- `Vaos.Ledger.Experiment.Scorer` - Quality scoring
- `Vaos.Ledger.Experiment.Loop` - Experiment cycle
- `Vaos.Ledger.Experiment.Strategy` - Strategy management

### Research Modules

- `Vaos.Ledger.Research.Pipeline` - Research pipeline
- `Vaos.Ledger.ML.Referee` - Trial monitoring

## Usage

```elixir
# Start the ledger application
{:ok, pid} = Vaos.Ledger.Epistemic.Ledger.start_link(path: "ledger.json")

# Create a claim
claim = Vaos.Ledger.add_claim(
  title: "Research hypothesis",
  statement: "Testable statement",
  novelty: 0.8,
  falsifiability: 0.7
)

# Get controller decision
decision = Vaos.Ledger.Epistemic.Controller.decide(Vaos.Ledger.Epistemic.Ledger)

# Rank actions
actions = Vaos.Ledger.Epistemic.Policy.rank_actions(Vaos.Ledger.Epistemic.Ledger)
```

## Dependencies

- `{:jason, "~> 1.4"}` - JSON serialization
- `{:req, "~> 0.5"}` - HTTP client
- `{:ex_doc, "~> 0.34", only: :dev, runtime: false}` - Documentation

## Development

```bash
# Run tests
mix test

# Compile
mix compile

# Generate docs
mix docs
```

## Port Status

This project is a port of the Python AIEQ-Core system to Elixir, with additional patterns from:
- `ex_autoresearch` - ML training monitoring
- `denario_ex` - Research pipeline patterns
- `swarma` - Experiment loop patterns

## License

MIT
