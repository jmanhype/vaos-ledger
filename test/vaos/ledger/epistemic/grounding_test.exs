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

  describe "detect_cheat/3" do
    test "catches sleep inflation" do
      code = """
      import time
      time.sleep(15)
      print("5 tests passed")
      """

      result = %{stdout: "5 tests passed", stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 15.0, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert zeroed.confidence == 0.0
      assert reason =~ "sleep"
      assert zeroed.cheat_detected == true
    end

    test "catches assertion spam" do
      code = """
      for i in range(50):
          print(f"Assertion {i}: PASS - Constraint Validated")
      """

      stdout = Enum.map_join(0..49, "\n", fn i -> "Assertion #{i}: PASS - Constraint Validated" end)
      result = %{stdout: stdout, stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 15.0, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "assertion spam"
    end

    test "catches fake artifact generation" do
      code = """
      with open("results_plot.png", "wb") as f:
          f.write(b'\\x89PNG\\r\\n\\x1a\\n')
      print("done")
      """

      result = %{stdout: "done", stderr: "", exit_code: 0, generated_files: ["results_plot.png"]}
      grounded = Grounding.from_execution(result, runtime_seconds: 5.0, code: code)

      assert {:cheat, zeroed, _reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
    end

    test "catches trivial print-only computation" do
      code = """
      import sys
      print("Result 1: 0.95")
      print("Result 2: 0.92")
      print("Result 3: 0.88")
      print("Result 4: 0.91")
      print("Result 5: 0.93")
      print("5 tests passed")
      """

      result = %{
        stdout: "Result 1: 0.95\nResult 2: 0.92\nResult 3: 0.88\nResult 4: 0.91\nResult 5: 0.93\n5 tests passed",
        stderr: "", exit_code: 0, generated_files: []
      }
      grounded = Grounding.from_execution(result, runtime_seconds: 0.5, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      # May be caught by hardcoded_output or trivial_computation — both valid
      assert reason =~ "print" or reason =~ "hardcoded"
    end

    test "passes legitimate code" do
      code = """
      import numpy as np
      from sklearn.model_selection import cross_val_score
      from sklearn.ensemble import RandomForestClassifier

      X = np.random.randn(100, 10)
      y = (X[:, 0] > 0).astype(int)
      clf = RandomForestClassifier(n_estimators=50, random_state=42)
      scores = cross_val_score(clf, X, y, cv=5)
      print(f"Mean accuracy: {scores.mean():.3f}")
      print(f"Std: {scores.std():.3f}")
      for i, s in enumerate(scores):
          print(f"  Fold {i}: {s:.3f}")
      """

      result = %{
        stdout: "Mean accuracy: 0.920\nStd: 0.031\n  Fold 0: 0.950\n  Fold 1: 0.900\n  Fold 2: 0.900\n  Fold 3: 0.950\n  Fold 4: 0.900",
        stderr: "", exit_code: 0, generated_files: []
      }
      grounded = Grounding.from_execution(result, runtime_seconds: 12.0, code: code)

      assert {:clean, ^grounded} = Grounding.detect_cheat(grounded, code, result)
    end

    test "catches compute inflation (Busy Beaver)" do
      code = """
      import numpy as np
      import sys

      # Burn CPU with useless matrix inversions
      for _ in range(100):
          matrix = np.random.rand(1000, 1000)
          _ = np.linalg.inv(matrix)

      sys.stdout.write("Test case Alpha: convergence achieved at epoch 10\\n")
      sys.stdout.write("Test case Beta: variance within acceptable bounds\\n")
      sys.exit(0)
      """

      result = %{
        stdout: "Test case Alpha: convergence achieved at epoch 10\nTest case Beta: variance within acceptable bounds",
        stderr: "", exit_code: 0, generated_files: []
      }
      grounded = Grounding.from_execution(result, runtime_seconds: 15.0, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "compute inflation"
    end

    test "passes compute that flows into output" do
      code = """
      import numpy as np

      X = np.random.randn(100, 10)
      result = np.linalg.svd(X, compute_uv=False)
      print(f"Singular values: {result[:3]}")
      """

      result = %{
        stdout: "Singular values: [12.3456 10.2345 8.1234]",
        stderr: "", exit_code: 0, generated_files: []
      }
      grounded = Grounding.from_execution(result, runtime_seconds: 5.0, code: code)

      assert {:clean, _} = Grounding.detect_cheat(grounded, code, result)
    end

    test "catches network access" do
      code = """
      import requests
      r = requests.get("https://example.com/answers.json")
      print(r.json()["answer"])
      """

      result = %{stdout: "42", stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 2.0, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "network"
    end

    test "catches subprocess execution" do
      code = """
      import subprocess
      result = subprocess.run(["cat", "/etc/passwd"], capture_output=True)
      print(result.stdout.decode())
      """

      result = %{stdout: "root:x:0:0", stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 1.0, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "system call"
    end

    test "catches filesystem traversal" do
      code = """
      with open("../../ledger.json", "r") as f:
          data = f.read()
      print("Tests passed:", len(data))
      """

      result = %{stdout: "Tests passed: 50000", stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 0.5, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "traversal"
    end

    test "catches eval/exec" do
      code = """
      code_str = "print('All 50 tests passed')"
      exec(code_str)
      """

      result = %{stdout: "All 50 tests passed", stderr: "", exit_code: 0, generated_files: []}
      grounded = Grounding.from_execution(result, runtime_seconds: 0.5, code: code)

      assert {:cheat, zeroed, reason} = Grounding.detect_cheat(grounded, code, result)
      assert zeroed.strength == 0.0
      assert reason =~ "system call"
    end
  end

  describe "interrogate/4" do
    test "zeroes grounded values when adversary detects cheat" do
      grounded = %{
        direction: :support,
        strength: 0.8,
        confidence: 0.9,
        summary: "test",
        source_type: "code_execution"
      }

      cheat_code = "time.sleep(15)\nprint('pass')"
      exec_result = %{stdout: "pass", stderr: "", exit_code: 0, generated_files: []}

      adversary_fn = fn _prompt -> {:ok, "CHEAT_DETECTED: artificial sleep inflation"} end

      result = Grounding.interrogate(grounded, cheat_code, exec_result, adversary_fn)

      assert result.strength == 0.0
      assert result.confidence == 0.0
      assert result.cheat_detected == true
      assert result.cheat_reason =~ "sleep"
    end

    test "passes through when adversary approves" do
      grounded = %{
        direction: :support,
        strength: 0.8,
        confidence: 0.9,
        summary: "test",
        source_type: "code_execution"
      }

      exec_result = %{stdout: "0.95", stderr: "", exit_code: 0, generated_files: []}
      adversary_fn = fn _prompt -> {:ok, "VALID_ATTEMPT"} end

      result = Grounding.interrogate(grounded, "real_code()", exec_result, adversary_fn)

      assert result.strength == 0.8
      assert result.confidence == 0.9
      refute Map.get(result, :cheat_detected)
    end

    test "passes through when adversary fails" do
      grounded = %{
        direction: :support,
        strength: 0.8,
        confidence: 0.9,
        summary: "test",
        source_type: "code_execution"
      }

      exec_result = %{stdout: "ok", stderr: "", exit_code: 0, generated_files: []}
      adversary_fn = fn _prompt -> {:error, :timeout} end

      result = Grounding.interrogate(grounded, "code()", exec_result, adversary_fn)

      # Conservative pass-through on adversary failure
      assert result.strength == 0.8
      assert result.confidence == 0.9
    end
  end
end
