defmodule VaosLedger.MixProject do
  use Mix.Project

  def project do
    [
      app: :vaos_ledger,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "VaosLedger",
      description: "V.A.O.S. Epistemic Governance and Auto-Research Engine"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VaosLedger.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
