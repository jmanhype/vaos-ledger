import Config

if config_env() == :test do
  config :vaos_ledger, skip_ledger_start: true
end
