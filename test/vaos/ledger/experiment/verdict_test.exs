defmodule Vaos.Ledger.Experiment.VerdictTest do
  use ExUnit.Case

  alias Vaos.Ledger.Experiment.Verdict

  describe "meets_threshold?/3" do
    test "returns true when best exceeds threshold" do
      assert Verdict.meets_threshold?(1.5, 1.0, 0.2)
    end

    test "returns false when best is below threshold" do
      refute Verdict.meets_threshold?(1.1, 1.0, 0.2)
    end

    test "uses default threshold of 0.2" do
      assert Verdict.meets_threshold?(1.25, 1.0)
      refute Verdict.meets_threshold?(1.15, 1.0)
    end

    test "handles zero baseline" do
      assert Verdict.meets_threshold?(0.5, 0.0)
    end
  end

  describe "keep_candidate?/4" do
    test "keeps candidate when score exceeds threshold" do
      candidate = %{score: 1.5}
      assert Verdict.keep_candidate?(candidate, 1.5, 1.0, 0.2)
    end

    test "rejects candidate below threshold" do
      candidate = %{score: 1.1}
      refute Verdict.keep_candidate?(candidate, 1.5, 1.0, 0.2)
    end
  end

  describe "verdict/6" do
    test "returns :converged when max iterations reached" do
      assert :converged = Verdict.verdict(0.5, 0.4, 0.3, 100, 100)
    end

    test "returns :plateau when threshold not met" do
      assert :plateau = Verdict.verdict(0.1, 0.09, 1.0, 5, 100)
    end

    test "returns :converged when improvement is small" do
      assert :converged = Verdict.verdict(1.5, 1.5, 1.0, 5, 100, 0.2)
    end

    test "returns :continue when still improving" do
      assert :continue = Verdict.verdict(1.8, 1.2, 1.0, 5, 100, 0.2)
    end
  end

  describe "improvement/2" do
    test "calculates improvement percentage" do
      assert_in_delta Verdict.improvement(1.5, 1.0), 0.5, 0.001
    end

    test "returns 0.0 for zero baseline" do
      assert Verdict.improvement(1.5, 0.0) == 0.0
    end

    test "handles negative improvement" do
      assert Verdict.improvement(0.5, 1.0) < 0
    end
  end

  describe "format_verdict/3" do
    test "formats continue verdict" do
      result = Verdict.format_verdict(:continue, 1.5, 1.0)
      assert String.contains?(result, "Continuing")
      assert String.contains?(result, "50.00%")
    end

    test "formats converged verdict" do
      result = Verdict.format_verdict(:converged, 1.2, 1.0)
      assert String.contains?(result, "Converged")
    end

    test "formats plateau verdict" do
      result = Verdict.format_verdict(:plateau, 0.5, 1.0)
      assert String.contains?(result, "Plateau")
    end

    test "handles zero baseline" do
      result = Verdict.format_verdict(:continue, 1.0, 0.0)
      assert String.contains?(result, "N/A")
    end
  end
end
