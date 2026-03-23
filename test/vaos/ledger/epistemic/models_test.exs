defmodule Vaos.Ledger.Epistemic.ModelsTest do
  use ExUnit.Case
  doctest Vaos.Ledger.Epistemic.Models

  alias Vaos.Ledger.Epistemic.Models

  describe "Claim" do
    test "creates new claim with defaults" do
      claim = Models.Claim.new(title: "Test", statement: "Test statement")

      assert claim.title == "Test"
      assert claim.statement == "Test statement"
      assert claim.status == :proposed
      assert claim.novelty == 0.5
      assert claim.falsifiability == 0.5
      assert claim.confidence == 0.0
      assert is_binary(claim.id)
      assert is_binary(claim.created_at)
      assert is_binary(claim.updated_at)
    end

    test "creates new claim with custom values" do
      claim = Models.Claim.new(
        title: "Test",
        statement: "Test statement",
        status: :active,
        novelty: 0.8,
        falsifiability: 0.9,
        confidence: 0.7
      )

      assert claim.status == :active
      assert claim.novelty == 0.8
      assert claim.falsifiability == 0.9
      assert claim.confidence == 0.7
    end

    test "clamps values to [0.0, 1.0]" do
      claim = Models.Claim.new(
        title: "Test",
        statement: "Test",
        novelty: 1.5,
        falsifiability: -0.5,
        confidence: 2.0
      )

      assert claim.novelty == 1.0
      assert claim.falsifiability == 0.0
      assert claim.confidence == 1.0
    end
  end

  describe "Assumption" do
    test "creates new assumption" do
      assumption = Models.Assumption.new(
        claim_id: "claim_1",
        text: "Test assumption"
      )

      assert assumption.claim_id == "claim_1"
      assert assumption.text == "Test assumption"
      assert assumption.risk == 0.5
      assert assumption.rationale == ""
      assert is_binary(assumption.id)
    end
  end

  describe "Evidence" do
    test "creates new evidence" do
      evidence = Models.Evidence.new(
        claim_id: "claim_1",
        summary: "Test evidence"
      )

      assert evidence.claim_id == "claim_1"
      assert evidence.summary == "Test evidence"
      assert evidence.direction == :inconclusive
      assert evidence.strength == 0.5
      assert evidence.confidence == 0.5
    end
  end

  describe "clamp/2" do
    test "clamps values within range" do
      assert Models.clamp(0.5, 0.0, 1.0) == 0.5
      assert Models.clamp(-0.5, 0.0, 1.0) == 0.0
      assert Models.clamp(1.5, 0.0, 1.0) == 1.0
    end

    test "uses default range [0.0, 1.0]" do
      assert Models.clamp(0.5) == 0.5
      assert Models.clamp(-1.0) == 0.0
      assert Models.clamp(2.0) == 1.0
    end
  end

  describe "utc_now/0" do
    test "returns ISO8601 timestamp" do
      timestamp = Models.utc_now()

      assert is_binary(timestamp)
      assert String.contains?(timestamp, "T")
      assert String.contains?(timestamp, "Z")
    end
  end
end
