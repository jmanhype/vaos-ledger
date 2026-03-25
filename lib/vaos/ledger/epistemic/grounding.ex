defmodule Vaos.Ledger.Epistemic.Grounding do
  @moduledoc """
  Derives evidence parameters from execution traces.

  Instead of trusting callers to supply strength, confidence, and direction,
  this module computes them deterministically from CodeExecutor output:
  `%{stdout, stderr, exit_code, generated_files}`.

  Design rationale: an LLM that generates a hypothesis AND grades its own
  execution will always report high confidence. Grounding removes the LLM
  from the self-grading loop by deriving epistemic weight from physical
  execution traces only.

  All functions are pure — no GenServer, no network, no side effects.
  """

  alias Vaos.Ledger.Epistemic.Models

  @type exec_result :: %{
          stdout: String.t(),
          stderr: String.t(),
          exit_code: integer(),
          generated_files: [String.t()]
        }

  @type grounded :: %{
          direction: :support | :contradict | :inconclusive,
          strength: float(),
          confidence: float(),
          summary: String.t(),
          source_type: String.t()
        }

  @doc """
  Derive evidence parameters from an execution trace.

  Takes a CodeExecutor result and optional runtime_seconds.
  Returns a map of `direction`, `strength`, `confidence`, `summary`,
  and `source_type` suitable for passing to `VaosLedger.add_evidence/1`.

  ## Parameters

    * `exec_result` - `%{stdout, stderr, exit_code, generated_files}`
    * `opts` - keyword list:
      * `:runtime_seconds` - wall-clock execution time (used for plausibility)
      * `:code` - the source code that was executed (used for substance check)

  ## Examples

      iex> result = %{stdout: "3 tests passed, 0 failed", stderr: "", exit_code: 0, generated_files: ["plot.png"]}
      iex> Grounding.from_execution(result, runtime_seconds: 12.5)
      %{direction: :support, strength: 0.72, confidence: 0.78, ...}
  """
  @spec from_execution(exec_result(), keyword()) :: grounded()
  def from_execution(exec_result, opts \\ []) do
    runtime = Keyword.get(opts, :runtime_seconds)
    code = Keyword.get(opts, :code, "")

    direction = derive_direction(exec_result)
    strength = derive_strength(exec_result, code)
    confidence = derive_confidence(exec_result, runtime)
    summary = derive_summary(exec_result, direction)

    %{
      direction: direction,
      strength: Models.clamp(strength),
      confidence: Models.clamp(confidence),
      summary: summary,
      source_type: "code_execution"
    }
  end

  @doc """
  Convert a grounded result to keyword attrs for `VaosLedger.add_evidence/1`.

  Merges the grounded parameters with caller-supplied attrs (claim_id, etc.).
  Grounded values take precedence over any caller-supplied strength/confidence/direction.
  """
  @spec to_evidence_attrs(grounded(), keyword()) :: keyword()
  def to_evidence_attrs(grounded, extra_attrs \\ []) do
    base = [
      direction: grounded.direction,
      strength: grounded.strength,
      confidence: grounded.confidence,
      summary: grounded.summary,
      source_type: grounded.source_type
    ]

    # Grounded values win over caller-supplied values
    extra_attrs
    |> Keyword.drop([:direction, :strength, :confidence, :summary, :source_type])
    |> Keyword.merge(base)
  end

  # --- Direction ---
  # Derived from exit_code + stdout content. No LLM involvement.

  defp derive_direction(%{exit_code: 0, stdout: stdout}) do
    cond do
      has_assertion_passes?(stdout) -> :support
      has_numeric_results?(stdout) -> :support
      substantive_output?(stdout) -> :support
      true -> :inconclusive
    end
  end

  defp derive_direction(%{exit_code: exit_code}) when exit_code != 0 do
    :contradict
  end

  # --- Strength ---
  # How definitively does this execution prove or disprove?
  # Factors: assertion count, output substance, error specificity, artifact generation.

  defp derive_strength(exec_result, code) do
    factors = [
      assertion_strength(exec_result.stdout),
      output_substance_strength(exec_result.stdout),
      artifact_strength(exec_result.generated_files),
      error_penalty(exec_result),
      code_substance_factor(code)
    ]

    # Geometric-ish mean: multiply factors, then root.
    # This means any single zero-factor kills the strength.
    product = Enum.reduce(factors, 1.0, &(&1 * &2))
    :math.pow(product, 1.0 / length(factors))
  end

  # Stdout contains test/assertion pass patterns
  defp assertion_strength(stdout) do
    patterns = [
      ~r/(\d+)\s+tests?\s+passed/i,
      ~r/(\d+)\s+passed/i,
      ~r/OK\s*\((\d+)\s+tests?\)/i,
      ~r/(\d+)\s+examples?,\s*0\s+failures/i,
      ~r/PASSED/i,
      ~r/assert.*true/i,
      ~r/✓|✔|PASS/
    ]

    matches = Enum.count(patterns, &Regex.match?(&1, stdout))

    # Extract actual assertion count if available
    count = extract_assertion_count(stdout)

    cond do
      count > 10 -> 0.9
      count > 3 -> 0.8
      count > 0 -> 0.7
      matches > 2 -> 0.65
      matches > 0 -> 0.55
      true -> 0.3
    end
  end

  defp extract_assertion_count(stdout) do
    patterns = [
      ~r/(\d+)\s+tests?\s+passed/i,
      ~r/(\d+)\s+passed/i,
      ~r/OK\s*\((\d+)\s+tests?\)/i,
      ~r/(\d+)\s+examples?/i
    ]

    patterns
    |> Enum.find_value(0, fn pattern ->
      case Regex.run(pattern, stdout) do
        [_, count_str] ->
          case Integer.parse(count_str) do
            {n, _} when n > 0 -> n
            _ -> nil
          end
        _ -> nil
      end
    end)
  end

  # Stdout has real content, not just "ok" or empty
  defp output_substance_strength(stdout) do
    trimmed = String.trim(stdout)
    byte_size = byte_size(trimmed)
    line_count = length(String.split(trimmed, "\n", trim: true))

    trivial_patterns = [
      ~r/\A(ok|done|success|true|completed\.?)\z/i,
      ~r/\A\d+\z/,
      ~r/\A\s*\z/
    ]

    is_trivial = Enum.any?(trivial_patterns, &Regex.match?(&1, trimmed))

    cond do
      byte_size == 0 -> 0.1
      is_trivial -> 0.2
      byte_size < 20 -> 0.3
      line_count > 10 and byte_size > 200 -> 0.9
      line_count > 3 and byte_size > 50 -> 0.7
      byte_size > 50 -> 0.6
      true -> 0.4
    end
  end

  # Generated files (plots, CSVs, etc.) are physical proof of work
  defp artifact_strength(generated_files) do
    count = length(generated_files || [])

    cond do
      count > 3 -> 0.9
      count > 1 -> 0.8
      count == 1 -> 0.7
      true -> 0.5
    end
  end

  # Stderr presence reduces strength (warnings/errors indicate fragility)
  defp error_penalty(%{exit_code: 0, stderr: stderr}) do
    stderr_size = byte_size(String.trim(stderr || ""))

    cond do
      stderr_size == 0 -> 1.0
      stderr_size < 100 -> 0.85
      stderr_size < 500 -> 0.7
      true -> 0.5
    end
  end

  defp error_penalty(%{exit_code: _}) do
    # Non-zero exit: this factor already captured in direction
    0.8
  end

  # Empty or trivial code = trivial result
  defp code_substance_factor(code) when is_binary(code) do
    trimmed = String.trim(code)
    line_count = length(String.split(trimmed, "\n", trim: true))

    cond do
      byte_size(trimmed) == 0 -> 0.5
      line_count < 3 -> 0.4
      line_count < 10 -> 0.7
      line_count < 50 -> 0.85
      true -> 0.9
    end
  end

  defp code_substance_factor(_), do: 0.5

  # --- Confidence ---
  # How trustworthy is this execution trace as a measurement?
  # Factors: runtime plausibility, stderr noise, reproducibility signals.

  defp derive_confidence(exec_result, runtime) do
    factors = [
      runtime_plausibility(runtime),
      stderr_noise_factor(exec_result.stderr),
      determinism_factor(exec_result.stdout)
    ]

    Enum.reduce(factors, 1.0, &(&1 * &2))
  end

  # Runtime plausibility: suspiciously fast or extremely slow = less trustworthy
  # Mirrors Scorer's inverted heuristic but for confidence rather than score.
  defp runtime_plausibility(nil), do: 0.6
  defp runtime_plausibility(seconds) when is_number(seconds) do
    cond do
      seconds < 0.5 -> 0.3   # Instant = likely no-op or cached
      seconds < 2.0 -> 0.5   # Suspiciously fast
      seconds < 10.0 -> 0.8  # Quick but plausible
      seconds < 60.0 -> 0.9  # Sweet spot for real computation
      seconds < 300.0 -> 0.85 # Long but reasonable
      true -> 0.6             # Very long = possibly hung/retry artifact
    end
  end

  # Stderr noise reduces confidence in the trace
  defp stderr_noise_factor(stderr) do
    stderr_size = byte_size(String.trim(stderr || ""))

    has_warnings = Regex.match?(~r/warning|deprecat/i, stderr || "")

    cond do
      stderr_size == 0 -> 1.0
      has_warnings and stderr_size < 200 -> 0.85
      stderr_size < 100 -> 0.9
      stderr_size < 500 -> 0.75
      true -> 0.6
    end
  end

  # If stdout contains randomness markers, confidence is lower
  # (non-deterministic results are harder to trust from a single run)
  defp determinism_factor(stdout) do
    non_deterministic_patterns = [
      ~r/random|seed|stochastic|monte.carlo/i,
      ~r/varies|fluctuat/i,
      ~r/±|plus.or.minus|margin.of.error/i
    ]

    if Enum.any?(non_deterministic_patterns, &Regex.match?(&1, stdout || "")) do
      0.7
    else
      1.0
    end
  end

  # --- Summary ---
  # Auto-generated from traces for provenance.

  defp derive_summary(exec_result, direction) do
    direction_str =
      case direction do
        :support -> "supports"
        :contradict -> "contradicts"
        :inconclusive -> "inconclusive for"
      end

    exit_str = "exit_code=#{exec_result.exit_code}"
    stdout_lines = length(String.split(exec_result.stdout || "", "\n", trim: true))
    artifact_count = length(exec_result.generated_files || [])

    parts = [
      "Execution #{direction_str} claim",
      "(#{exit_str}, #{stdout_lines} output lines"
    ]

    parts =
      if artifact_count > 0 do
        parts ++ [", #{artifact_count} artifacts"]
      else
        parts
      end

    Enum.join(parts, " ") <> ")"
  end

  # --- Helpers ---

  defp has_assertion_passes?(stdout) do
    Regex.match?(~r/\d+\s+(tests?\s+)?passed|OK\s*\(\d+|PASS|✓|✔/i, stdout || "")
  end

  defp has_numeric_results?(stdout) do
    # Numeric output suggests actual computation (not just "ok")
    Regex.match?(~r/\d+\.\d+.*\d+\.\d+/s, stdout || "")
  end

  defp substantive_output?(stdout) do
    trimmed = String.trim(stdout || "")
    lines = String.split(trimmed, "\n", trim: true)
    byte_size(trimmed) > 100 and length(lines) > 3
  end
end
