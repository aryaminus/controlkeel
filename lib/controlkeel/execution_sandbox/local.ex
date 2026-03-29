defmodule ControlKeel.ExecutionSandbox.Local do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @impl true
  def run(command, args, opts) do
    env = Keyword.get(opts, :env, [])
    cwd = Keyword.get(opts, :cwd)

    run_opts = [stderr_to_stdout: true]
    run_opts = if cwd, do: Keyword.put(run_opts, :cd, cwd), else: run_opts

    try do
      {output, exit_status} = System.cmd(command, args, run_opts ++ [env: env])
      {:ok, %{output: output, exit_status: exit_status}}
    rescue
      e -> {:error, {:execution_failed, Exception.message(e)}}
    end
  end

  @impl true
  def available?, do: true

  @impl true
  def adapter_name, do: "local"
end
