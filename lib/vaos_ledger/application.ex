defmodule VaosLedger.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Default ledger path
    ledger_path = Application.get_env(:vaos_ledger, :ledger_path, "ledger.json")

    children = [
      # Ledger GenServer
      {Vaos.Ledger.Epistemic.Ledger, path: ledger_path}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VaosLedger.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
