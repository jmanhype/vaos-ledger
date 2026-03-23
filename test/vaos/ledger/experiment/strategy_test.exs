defmodule Vaos.Ledger.Experiment.StrategyTest do
  use ExUnit.Case

  alias Vaos.Ledger.Experiment.Strategy

  describe "load/1" do
    test "returns default strategy when no file exists" do
      {:ok, strategy} = Strategy.load("/tmp/nonexistent_dir_#{:rand.uniform(999999)}")
      assert strategy.name == "default"
      assert is_list(strategy.goals)
      assert is_list(strategy.constraints)
      assert is_map(strategy.hyperparameters)
    end
  end

  describe "save/2" do
    test "saves strategy to file" do
      dir = Path.join(System.tmp_dir!(), "strategy_test_#{:rand.uniform(999999)}")
      File.mkdir_p!(dir)
      {:ok, strategy} = Strategy.load(dir)
      {:ok, path} = Strategy.save(strategy, dir)
      assert File.exists?(path)
      File.rm_rf!(dir)
    end
  end

  describe "evolve/2" do
    test "evolves strategy based on metrics" do
      {:ok, strategy} = Strategy.load()
      metrics = %{score: 0.9, runtime: 3.0, best_score: 0.9, iteration: 5}
      {:ok, evolved} = Strategy.evolve(strategy, metrics)
      assert length(evolved.evolution_history) == 1
    end

    test "adjusts learning rate down for poor scores" do
      {:ok, strategy} = Strategy.load()
      original_lr = Strategy.get_hyperparameter(strategy, "learning_rate")
      metrics = %{score: 0.1, runtime: 30.0, best_score: 0.1, iteration: 1}
      {:ok, evolved} = Strategy.evolve(strategy, metrics)
      new_lr = Strategy.get_hyperparameter(evolved, "learning_rate")
      assert new_lr < original_lr
    end

    test "adjusts learning rate up for good+fast scores" do
      {:ok, strategy} = Strategy.load()
      original_lr = Strategy.get_hyperparameter(strategy, "learning_rate")
      metrics = %{score: 0.9, runtime: 5.0, best_score: 0.9, iteration: 1}
      {:ok, evolved} = Strategy.evolve(strategy, metrics)
      new_lr = Strategy.get_hyperparameter(evolved, "learning_rate")
      assert new_lr > original_lr
    end
  end

  describe "get_hyperparameter/3 and set_hyperparameter/3" do
    test "gets and sets hyperparameters" do
      {:ok, strategy} = Strategy.load()
      assert Strategy.get_hyperparameter(strategy, "learning_rate") == 0.01
      assert Strategy.get_hyperparameter(strategy, "missing", 42) == 42

      updated = Strategy.set_hyperparameter(strategy, "learning_rate", 0.05)
      assert Strategy.get_hyperparameter(updated, "learning_rate") == 0.05
    end
  end

  describe "summary/1" do
    test "returns formatted markdown summary" do
      {:ok, strategy} = Strategy.load()
      text = Strategy.summary(strategy)
      assert String.contains?(text, "Strategy: default")
      assert String.contains?(text, "Goals")
      assert String.contains?(text, "Constraints")
      assert String.contains?(text, "Hyperparameters")
    end
  end
end
