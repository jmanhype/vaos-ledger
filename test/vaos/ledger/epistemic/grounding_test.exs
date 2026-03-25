defmodule Vaos.Ledger.Epistemic.GroundingTest do
  use ExUnit.Case

  alias Vaos.Ledger.Epistemic.Grounding

  describe "from_execution/2" do
    test "successful execution with assertions → :support with high strength" do
      result = %{
        stdout: "Running tests...\n12 tests passed, 0 failed\nAll assertions verified.",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      grounded = Grounding.from_execution(result, runtime_seconds: 15.0)

      assert grounded.direction == :support
      assert grounded.strength > 0.5
      assert grounded.confidence > 0.5
      assert grounded.source_type == "code_execution"
      assert is_binary(grounded.summary)
    end

    test "failed execution → :contradict" do
      result = %{
        stdout: "",
        stderr: "Traceback (most recent call last):\n  File \"test.py\", line 5\nAssertionError",
        exit_code: 1,
        generated_files: []
      }

      grounded = Grounding.from_execution(result, runtime_seconds: 2.0)

      assert grounded.direction == :contradict
      assert grounded.source_type == "code_execution"
    end

    test "exit 0 but empty stdout → :inconclusive" do
      result = %{
        stdout: "",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      grounded = Grounding.from_execution(result)

      assert grounded.direction == :inconclusive
    end

    test "exit 0 with trivial output → :inconclusive" do
      result = %{
        stdout: "ok",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      grounded = Grounding.from_execution(result)

      assert grounded.direction == :inconclusive
    end

    test "exit 0 with numeric results → :support" do
      result = %{
        stdout: "accuracy: 0.923\nprecision: 0.891\nrecall: 0.945\nf1: 0.917",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      grounded = Grounding.from_execution(result, runtime_seconds: 45.0)

      assert grounded.direction == :support
    end

    test "generated artifacts increase strength" do
      base = %{
        stdout: "Experiment complete.\n5 tests passed",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      with_artifacts = %{base | generated_files: ["plot.png", "results.csv", "model.pkl"]}

      g_base = Grounding.from_execution(base, runtime_seconds: 30.0)
      g_artifacts = Grounding.from_execution(with_artifacts, runtime_seconds: 30.0)

      assert g_artifacts.strength > g_base.strength
    end

    test "suspiciously fast runtime reduces confidence" do
      result = %{
        stdout: "5 tests passed",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      fast = Grounding.from_execution(result, runtime_seconds: 0.1)
      moderate = Grounding.from_execution(result, runtime_seconds: 30.0)

      assert moderate.confidence > fast.confidence
    end

    test "stderr warnings reduce confidence" do
      clean = %{
        stdout: "5 tests passed",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      noisy = %{clean | stderr: "DeprecationWarning: use of deprecated function\nwarning: implicit conversion"}

      g_clean = Grounding.from_execution(clean, runtime_seconds: 30.0)
      g_noisy = Grounding.from_execution(noisy, runtime_seconds: 30.0)

      assert g_clean.confidence > g_noisy.confidence
    end

    test "no runtime provided gives lower confidence than plausible runtime" do
      result = %{
        stdout: "5 tests passed",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      no_runtime = Grounding.from_execution(result)
      with_runtime = Grounding.from_execution(result, runtime_seconds: 30.0)

      assert with_runtime.confidence > no_runtime.confidence
    end

    test "stochastic output markers reduce confidence" do
      deterministic = %{
        stdout: "Result: 42.0\nVerified.",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      stochastic = %{
        stdout: "Monte Carlo simulation: mean=42.0 ±3.2\nRandom seed: 12345",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      g_det = Grounding.from_execution(deterministic, runtime_seconds: 30.0)
      g_stoch = Grounding.from_execution(stochastic, runtime_seconds: 30.0)

      assert g_det.confidence > g_stoch.confidence
    end

    test "all values are clamped to [0.0, 1.0]" do
      result = %{
        stdout: String.duplicate("test passed\n", 100),
        stderr: "",
        exit_code: 0,
        generated_files: Enum.map(1..10, &"file_#{&1}.png")
      }

      grounded = Grounding.from_execution(result, runtime_seconds: 30.0)

      assert grounded.strength >= 0.0 and grounded.strength <= 1.0
      assert grounded.confidence >= 0.0 and grounded.confidence <= 1.0
    end

    test "code substance affects strength" do
      result = %{
        stdout: "5 tests passed",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      trivial_code = "print('ok')"

      real_code = """
      import numpy as np
      from sklearn.model_selection import cross_val_score
      from sklearn.ensemble import RandomForestClassifier

      X = np.load('data.npy')
      y = np.load('labels.npy')
      clf = RandomForestClassifier(n_estimators=100)
      scores = cross_val_score(clf, X, y, cv=5)
      print(f'{len(scores)} tests passed')
      for s in scores:
          print(f'  fold score: {s:.3f}')
      """

      g_trivial = Grounding.from_execution(result, runtime_seconds: 30.0, code: trivial_code)
      g_real = Grounding.from_execution(result, runtime_seconds: 30.0, code: real_code)

      assert g_real.strength > g_trivial.strength
    end
  end

  describe "to_evidence_attrs/2" do
    test "merges grounded values with extra attrs" do
      grounded = %{
        direction: :support,
        strength: 0.75,
        confidence: 0.8,
        summary: "Execution supports claim (exit_code=0, 5 output lines)",
        source_type: "code_execution"
      }

      attrs = Grounding.to_evidence_attrs(grounded, claim_id: "claim_123", actor_id: "agent_1")

      assert Keyword.get(attrs, :claim_id) == "claim_123"
      assert Keyword.get(attrs, :actor_id) == "agent_1"
      assert Keyword.get(attrs, :direction) == :support
      assert Keyword.get(attrs, :strength) == 0.75
      assert Keyword.get(attrs, :confidence) == 0.8
      assert Keyword.get(attrs, :source_type) == "code_execution"
    end

    test "grounded values override caller-supplied strength/confidence" do
      grounded = %{
        direction: :contradict,
        strength: 0.3,
        confidence: 0.6,
        summary: "Execution contradicts claim",
        source_type: "code_execution"
      }

      # Caller tries to override with high values
      attrs = Grounding.to_evidence_attrs(grounded,
        claim_id: "claim_123",
        strength: 0.99,
        confidence: 0.99,
        direction: :support
      )

      # Grounded values must win
      assert Keyword.get(attrs, :strength) == 0.3
      assert Keyword.get(attrs, :confidence) == 0.6
      assert Keyword.get(attrs, :direction) == :contradict
    end
  end

  describe "summary generation" do
    test "includes direction, exit code, and line count" do
      result = %{
        stdout: "line1\nline2\nline3",
        stderr: "",
        exit_code: 0,
        generated_files: []
      }

      grounded = Grounding.from_execution(result)

      assert grounded.summary =~ "exit_code=0"
      assert grounded.summary =~ "3 output lines"
    end

    test "includes artifact count when present" do
      result = %{
        stdout: "5 tests passed\nAll good",
        stderr: "",
        exit_code: 0,
        generated_files: ["plot.png", "data.csv"]
      }

      grounded = Grounding.from_execution(result)

      assert grounded.summary =~ "2 artifacts"
    end
  end
end
