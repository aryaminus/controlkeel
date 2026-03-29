defmodule ControlKeel.ExecutionSandbox.E2B do
  @moduledoc false

  @behaviour ControlKeel.ExecutionSandbox

  @default_template "base"

  @impl true
  def run(command, args, opts) do
    api_key = resolve_api_key(opts)
    template = Keyword.get(opts, :e2b_template, config_template())
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, 300)

    with {:ok, sandbox_id} <- create_sandbox(api_key, template, timeout),
         :ok <- maybe_upload_project(sandbox_id, cwd, api_key),
         {:ok, output, exit_status} <-
           execute_in_sandbox(sandbox_id, command, args, env, api_key, cwd),
         :ok <- cleanup_sandbox(sandbox_id, api_key) do
      {:ok, %{output: output, exit_status: exit_status}}
    else
      {:error, reason} -> {:error, {:e2b_execution_failed, reason}}
    end
  end

  @impl true
  def available? do
    api_key = resolve_api_key([])
    is_binary(api_key) and byte_size(api_key) > 0
  end

  @impl true
  def adapter_name, do: "e2b"

  defp resolve_api_key(opts) do
    Keyword.get(opts, :e2b_api_key) ||
      System.get_env("E2B_API_KEY") ||
      read_e2b_config()["api_key"]
  end

  defp create_sandbox(api_key, template, timeout) do
    body =
      Jason.encode!(%{
        templateID: template,
        metadata: %{"source" => "controlkeel"},
        timeoutMs: timeout * 1000
      })

    case req_post("https://api.e2b.dev/sandboxes", body, api_key) do
      {:ok, %{"sandboxID" => sandbox_id}} -> {:ok, sandbox_id}
      {:ok, %{"sandboxId" => sandbox_id}} -> {:ok, sandbox_id}
      {:error, reason} -> {:error, {:sandbox_create_failed, reason}}
    end
  end

  defp execute_in_sandbox(sandbox_id, command, args, env, api_key, cwd) do
    full_command = Enum.join([command | args], " ")

    env_prefix =
      env
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(" ")

    shell_command =
      cond do
        env_prefix != "" and cwd -> "cd #{cwd} && #{env_prefix} #{full_command}"
        cwd -> "cd #{cwd} && #{full_command}"
        env_prefix != "" -> "#{env_prefix} #{full_command}"
        true -> full_command
      end

    body = Jason.encode!(%{code: shell_command})

    case req_post("https://api.e2b.dev/sandboxes/#{sandbox_id}/execute", body, api_key) do
      {:ok, %{"stdout" => stdout, "exitCode" => exit_code}} ->
        {:ok, stdout || "", exit_code || 0}

      {:ok, %{"error" => error}} ->
        {:error, {:execution_error, error}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_upload_project(_sandbox_id, nil, _api_key), do: :ok

  defp maybe_upload_project(sandbox_id, cwd, api_key) do
    abs_path = Path.expand(cwd)

    unless File.dir?(abs_path) do
      :ok
    else
      case File.ls(abs_path) do
        {:ok, [_ | _] = files} ->
          tar_path = Path.join(System.tmp_dir!(), "ck-e2b-#{sandbox_id}.tar.gz")

          try do
            {_, 0} =
              System.cmd("tar", ["czf", tar_path, "-C", abs_path] ++ files,
                stderr_to_stdout: true
              )

            upload_sandbox_files(sandbox_id, tar_path, api_key)
          after
            File.rm(tar_path)
          end

        _ ->
          :ok
      end
    end
  end

  defp upload_sandbox_files(sandbox_id, tar_path, api_key) do
    case File.read(tar_path) do
      {:ok, tar_data} ->
        headers = [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/gzip"}
        ]

        case Req.post(
               "https://api.e2b.dev/sandboxes/#{sandbox_id}/upload",
               body: tar_data,
               headers: headers
             ) do
          {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
          {:error, reason} -> {:error, {:upload_failed, reason}}
        end

      _ ->
        :ok
    end
  end

  defp cleanup_sandbox(sandbox_id, api_key) do
    _ =
      Req.delete("https://api.e2b.dev/sandboxes/#{sandbox_id}",
        headers: [{"Authorization", "Bearer #{api_key}"}]
      )

    :ok
  end

  defp req_post(url, body, api_key) do
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        case resp_body do
          %{} = decoded -> {:ok, decoded}
          _ -> {:ok, %{}}
        end

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config_template do
    case read_e2b_config() do
      %{"template" => template} when is_binary(template) -> template
      _ -> @default_template
    end
  end

  defp read_e2b_config do
    path = ControlKeel.RuntimePaths.config_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"execution_sandbox_e2b" => %{} = e2b_config}} -> e2b_config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end
end
