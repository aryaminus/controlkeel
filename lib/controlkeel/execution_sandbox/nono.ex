defmodule ControlKeel.ExecutionSandbox.Nono do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @default_profile "auto"
  @default_allow_cwd true
  @default_allow_net false
  @default_rollback true

  @impl true
  def run(command, args, opts) do
    env = Keyword.get(opts, :env, [])
    cwd = Keyword.get(opts, :cwd)
    nono_args = build_nono_args(command, args, cwd, opts)

    run_opts = [stderr_to_stdout: true, env: env]
    run_opts = if cwd, do: Keyword.put(run_opts, :cd, cwd), else: run_opts

    try do
      {output, exit_status} = System.cmd("nono", nono_args, run_opts)
      {:ok, %{output: output, exit_status: exit_status}}
    rescue
      e -> {:error, {:nono_execution_failed, Exception.message(e)}}
    end
  end

  @impl true
  def available? do
    case System.cmd("nono", ["--version"], stderr_to_stdout: true) do
      {output, 0} when is_binary(output) ->
        byte_size(String.trim(output)) > 0

      _ ->
        false
    end
  rescue
    _ -> false
  end

  @impl true
  def adapter_name, do: "nono"

  defp build_nono_args(command, args, cwd, opts) do
    config = read_nono_config()
    profile = Keyword.get(opts, :nono_profile, Map.get(config, "profile", @default_profile))

    allow_cwd? =
      Keyword.get(opts, :nono_allow_cwd, Map.get(config, "allow_cwd", @default_allow_cwd))

    allow_net? =
      Keyword.get(opts, :nono_allow_net, Map.get(config, "allow_net", @default_allow_net))

    rollback? = Keyword.get(opts, :nono_rollback, Map.get(config, "rollback", @default_rollback))
    extra_allow = Keyword.get(opts, :nono_allow, Map.get(config, "allow", []))

    ["run"] ++
      profile_args(profile, command) ++
      maybe_allow_cwd(cwd, allow_cwd?) ++
      allow_flags(extra_allow) ++
      rollback_flags(rollback?) ++
      maybe_allow_net(allow_net?) ++ ["--", command] ++ args
  end

  defp profile_args("auto", command) do
    case inferred_profile(command) do
      nil -> []
      profile -> ["--profile", profile]
    end
  end

  defp profile_args(profile, _command) when is_binary(profile) and profile != "" do
    ["--profile", profile]
  end

  defp profile_args(_, _command), do: []

  defp maybe_allow_cwd(cwd, true) when is_binary(cwd) and cwd != "", do: ["--allow-cwd"]
  defp maybe_allow_cwd(_, _), do: []

  defp allow_flags(paths) when is_list(paths) do
    Enum.flat_map(paths, fn
      path when is_binary(path) and path != "" -> ["--allow", path]
      _ -> []
    end)
  end

  defp allow_flags(_), do: []

  defp rollback_flags(true), do: ["--rollback"]
  defp rollback_flags(false), do: ["--no-rollback"]
  defp rollback_flags(_), do: []

  defp maybe_allow_net(true), do: ["--allow-net"]
  defp maybe_allow_net(_), do: []

  defp inferred_profile(command) do
    case Path.basename(command) do
      "claude" -> "claude-code"
      "codex" -> "codex"
      "opencode" -> "opencode"
      "openclaw" -> "openclaw"
      "swival" -> "swival"
      _ -> nil
    end
  end

  defp read_nono_config do
    path = ControlKeel.RuntimePaths.config_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"execution_sandbox_nono" => %{} = config}} -> config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
