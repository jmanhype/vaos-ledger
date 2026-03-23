defmodule VaosLedger.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        # In test mode, don't auto-start the Ledger GenServer.
        # Each test module starts its own instance.
        []
      else
        ledger_path = Application.get_env(:vaos_ledger, :ledger_path, "ledger.json")
        [{Vaos.Ledger.Epistemic.Ledger, path: ledger_path}]
      end

    opts = [strategy: :one_for_one, name: VaosLedger.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
