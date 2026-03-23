defmodule Vaos.Ledger.Research.CodeExecutor do
  @moduledoc """
  Sandboxed code execution with timeout and retry logic.
  Ported from denario_ex's PythonExecutor + ResultsWorkflow retry pattern.

  All execution goes through an injected code_fn callback, making it
  testable and runtime-agnostic (Python, Elixir, shell, etc.).
  """

  require Logger

  @type exec_result :: %{
          stdout: String.t(),
          stderr: String.t(),
          exit_code: integer(),
          generated_files: [String.t()]
        }

  @type code_fn ::
          (String.t(), keyword() ->
             {:ok, %{stdout: String.t(), stderr: String.t()}} | {:error, term()})

  @default_max_attempts 3
  @default_timeout_ms 60_000

  @doc """
  Execute code with retry logic. On failure, passes the error output back
  to an optional fix_fn callback that can rewrite the code before retrying.

  Options:
    - :max_attempts - maximum retry count (default: 3)
    - :timeout_ms - timeout per attempt in ms (default: 60_000)
    - :work_dir - working directory for execution
    - :step_id - identifier for logging
    - :fix_fn - optional (code, error) -> {:ok, new_code} | :give_up callback
  """
  @spec execute_with_retry(String.t(), code_fn(), keyword()) ::
          {:ok, exec_result()} | {:error, term()}
  def execute_with_retry(code, code_fn, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    step_id = Keyword.get(opts, :step_id, "step")

    do_execute(code, code_fn, opts, step_id, 1, max_attempts)
  end

  @doc """
  Execute code once (no retry). Wraps the code_fn with timeout handling.
  """
  @spec execute(String.t(), code_fn(), keyword()) :: {:ok, exec_result()} | {:error, term()}
  def execute(code, code_fn, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    work_dir = Keyword.get(opts, :work_dir)

    code_opts =
      opts
      |> Keyword.take([:work_dir, :step_id, :env])
      |> Keyword.put_new(:timeout_ms, timeout_ms)

    task =
      Task.async(fn ->
        code_fn.(code, code_opts)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        generated = collect_generated_files(work_dir)

        {:ok,
         %{
           stdout: Map.get(result, :stdout, ""),
           stderr: Map.get(result, :stderr, ""),
           exit_code: Map.get(result, :exit_code, 0),
           generated_files: generated
         }}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, {:timeout, timeout_ms}}
    end
  end

  # -- Private --

  defp do_execute(_code, _code_fn, _opts, step_id, attempt, max_attempts)
       when attempt > max_attempts do
    Logger.error("Code execution failed after #{max_attempts} attempts for #{step_id}")
    {:error, {:max_attempts_exceeded, step_id, max_attempts}}
  end

  defp do_execute(code, code_fn, opts, step_id, attempt, max_attempts) do
    Logger.info("Executing #{step_id} attempt #{attempt}/#{max_attempts}")

    case execute(code, code_fn, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < max_attempts ->
        fix_fn = Keyword.get(opts, :fix_fn)
        error_text = format_error(reason)

        Logger.warning(
          "Execution failed for #{step_id} attempt #{attempt}: #{error_text}"
        )

        case maybe_fix_code(fix_fn, code, error_text) do
          {:ok, new_code} ->
            do_execute(new_code, code_fn, opts, step_id, attempt + 1, max_attempts)

          :give_up ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_fix_code(nil, _code, _error), do: :give_up

  defp maybe_fix_code(fix_fn, code, error) when is_function(fix_fn, 2) do
    fix_fn.(code, error)
  end

  defp format_error({:timeout, ms}), do: "Timed out after #{ms}ms"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp collect_generated_files(nil), do: []

  defp collect_generated_files(work_dir) do
    ["png", "jpg", "jpeg", "pdf", "svg", "csv", "json"]
    |> Enum.flat_map(fn ext -> Path.wildcard(Path.join(work_dir, "**/*.#{ext}")) end)
    |> Enum.uniq()
  end
end
