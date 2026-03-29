defmodule ControlKeel.ExecutionSandbox.Docker do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @default_image "controlkeel/agent-runner:latest"

  @impl true
  def run(command, args, opts) do
    env = Keyword.get(opts, :env, [])
    cwd = Keyword.get(opts, :cwd)
    image = Keyword.get(opts, :docker_image, config_image())
    timeout = Keyword.get(opts, :timeout, 600)

    docker_args = build_docker_args(command, args, env, cwd, image, timeout)

    try do
      {output, exit_status} = System.cmd("docker", docker_args, stderr_to_stdout: true)
      {:ok, %{output: output, exit_status: exit_status}}
    rescue
      e -> {:error, {:docker_execution_failed, Exception.message(e)}}
    end
  end

  @impl true
  def available? do
    case System.cmd("docker", ["version", "--format", "{{.Client.Version}}"],
           stderr_to_stdout: true
         ) do
      {output, 0} when is_binary(output) and byte_size(output) > 0 -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def adapter_name, do: "docker"

  defp build_docker_args(command, args, env, cwd, image, timeout) do
    base = ["run", "--rm"]

    env_flags =
      env
      |> Enum.flat_map(fn {k, v} -> ["-e", "#{k}=#{v}"] end)

    volume_flags =
      if cwd do
        ["-v", "#{Path.expand(cwd)}:/workspace:rw", "-w", "/workspace"]
      else
        []
      end

    resource_flags =
      ["--memory", config_memory_limit(), "--cpus", config_cpu_limit()] ++
        timeout_flag(timeout) ++
        network_flag()

    base ++ env_flags ++ volume_flags ++ resource_flags ++ [image, command] ++ args
  end

  defp timeout_flag(timeout) when is_integer(timeout) and timeout > 0,
    do: ["--stop-timeout", to_string(timeout)]

  defp timeout_flag(_), do: []

  defp network_flag do
    case config_network() do
      "none" -> ["--network", "none"]
      "host" -> ["--network", "host"]
      _ -> []
    end
  end

  defp config_image do
    case read_docker_config() do
      %{"image" => image} when is_binary(image) -> image
      _ -> @default_image
    end
  end

  defp config_memory_limit do
    case read_docker_config() do
      %{"memory_limit" => limit} when is_binary(limit) -> limit
      _ -> "512m"
    end
  end

  defp config_cpu_limit do
    case read_docker_config() do
      %{"cpu_limit" => limit} when is_binary(limit) -> limit
      _ -> "1"
    end
  end

  defp config_network do
    case read_docker_config() do
      %{"network" => network} when network in ["none", "host", "bridge"] -> network
      _ -> "none"
    end
  end

  defp read_docker_config do
    path = ControlKeel.RuntimePaths.config_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"execution_sandbox_docker" => %{} = docker_config}} -> docker_config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
