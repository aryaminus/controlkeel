defmodule ControlKeel.Updater do
  @moduledoc false

  alias ControlKeel.AttachedAgentSync
  alias ControlKeel.CLI
  alias ControlKeel.ProjectBinding

  @repository "aryaminus/controlkeel"
  @npm_package "@aryaminus/controlkeel"

  def check(project_root, opts \\ []) do
    current_version = CLI.version()
    executable_path = Keyword.get(opts, :executable_path, System.find_executable("controlkeel"))
    cmd_runner = Keyword.get(opts, :cmd_runner, &default_cmd/3)

    latest =
      case fetch_latest_release(Keyword.get(opts, :http_get, &default_http_get/1), opts) do
        {:ok, release} ->
          release

        {:error, reason} ->
          %{
            "status" => "error",
            "error" => format_reason(reason),
            "version" => nil,
            "url" => release_page_url(opts)
          }
      end

    install = detect_install_channel(executable_path, cmd_runner)
    attached = attached_status(project_root, current_version)

    %{
      "current_version" => current_version,
      "latest_release" => latest,
      "update_available" => update_available?(current_version, latest["version"]),
      "install" => install,
      "attached" => attached,
      "commands" => recommended_commands(install, current_version, latest, attached)
    }
  end

  def apply(project_root, opts \\ []) do
    report = check(project_root, opts)

    report =
      if Keyword.get(opts, :apply, false) do
        Map.put(report, "apply_result", apply_self_update(report, opts))
      else
        Map.put(report, "apply_result", %{
          "status" => "skipped",
          "reason" => "apply_not_requested"
        })
      end

    report =
      if Keyword.get(opts, :sync_attached, false) do
        Map.put(report, "sync_result", sync_attached(project_root, report))
      else
        Map.put(report, "sync_result", %{"status" => "skipped", "reason" => "sync_not_requested"})
      end

    {:ok, report}
  end

  def render(report) do
    latest = report["latest_release"] || %{}
    install = report["install"] || %{}
    attached = report["attached"] || %{}
    commands = report["commands"] || %{}

    lines = [
      "ControlKeel update status",
      "Current version: #{report["current_version"]}",
      "Latest release: #{latest["version"] || "unknown"}",
      "Release source: #{latest["url"] || release_page_url()}",
      "Update available: #{yes_no(report["update_available"])}",
      "Install channel: #{install["channel"] || "unknown"}",
      "Executable: #{install["executable_path"] || "not found"}",
      "Attached surfaces tracked: #{attached["installed_count"] || 0}",
      "Attached surfaces stale: #{attached["stale_count"] || 0}"
    ]

    lines =
      case latest["error"] do
        error when is_binary(error) -> lines ++ ["Latest release check: #{error}"]
        _ -> lines
      end

    lines =
      case commands["self_update"] do
        command when is_binary(command) -> lines ++ ["Recommended self update: #{command}"]
        _ -> lines
      end

    case commands["attached_sync"] do
      command when is_binary(command) -> lines ++ ["Recommended attached sync: #{command}"]
      _ -> lines
    end
  end

  defp apply_self_update(%{"update_available" => false}, _opts) do
    %{"status" => "noop", "message" => "ControlKeel is already on the latest release."}
  end

  defp apply_self_update(%{"latest_release" => %{"version" => nil}}, _opts) do
    %{"status" => "error", "message" => "Unable to determine the latest GitHub release."}
  end

  defp apply_self_update(report, opts) do
    install = report["install"] || %{}
    channel = install["channel"] || "unknown"
    cmd_runner = Keyword.get(opts, :cmd_runner, &default_cmd/3)

    case channel do
      "brew" ->
        case cmd_runner.("brew", ["upgrade", "controlkeel"], stderr_to_stdout: true) do
          {output, 0} ->
            %{"status" => "applied", "channel" => channel, "message" => String.trim(output)}

          {output, status} ->
            %{
              "status" => "error",
              "channel" => channel,
              "message" => "brew upgrade exited with status #{status}: #{String.trim(output)}"
            }
        end

      "npm" ->
        case cmd_runner.("npm", ["i", "-g", "#{@npm_package}@latest"], stderr_to_stdout: true) do
          {output, 0} ->
            %{"status" => "applied", "channel" => channel, "message" => String.trim(output)}

          {output, status} ->
            %{
              "status" => "error",
              "channel" => channel,
              "message" => "npm install exited with status #{status}: #{String.trim(output)}"
            }
        end

      "github_release_binary" ->
        apply_direct_binary_update(report, opts)

      _ ->
        %{
          "status" => "manual",
          "channel" => channel,
          "message" =>
            "Automatic self update is not supported for this install channel. Use the recommended command."
        }
    end
  end

  defp apply_direct_binary_update(report, opts) do
    path = get_in(report, ["install", "executable_path"])

    cond do
      is_nil(path) ->
        %{
          "status" => "error",
          "channel" => "github_release_binary",
          "message" => "Executable path not found."
        }

      match?({:win32, _}, :os.type()) ->
        %{
          "status" => "manual",
          "channel" => "github_release_binary",
          "message" =>
            "Automatic in-place replacement is not supported on Windows. Re-run the PowerShell installer."
        }

      true ->
        downloader = Keyword.get(opts, :download_binary, &download_release_binary/2)
        latest_version = get_in(report, ["latest_release", "version"])

        case downloader.(latest_version, opts) do
          {:ok, downloaded_path} ->
            with :ok <- File.cp(downloaded_path, path),
                 :ok <- File.chmod(path, 0o755) do
              %{
                "status" => "applied",
                "channel" => "github_release_binary",
                "message" => "Replaced #{path} with ControlKeel #{latest_version}."
              }
            else
              {:error, reason} ->
                %{
                  "status" => "error",
                  "channel" => "github_release_binary",
                  "message" => "Failed to replace #{path}: #{inspect(reason)}"
                }
            end

          {:error, reason} ->
            %{
              "status" => "error",
              "channel" => "github_release_binary",
              "message" => "Failed to download the latest binary: #{format_reason(reason)}"
            }
        end
    end
  end

  defp sync_attached(project_root, report) do
    case get_in(report, ["apply_result", "status"]) do
      "applied" ->
        %{
          "status" => "skipped",
          "reason" => "rerun_after_self_update",
          "message" =>
            "Rerun `controlkeel update --sync-attached` after the new ControlKeel binary is active."
        }

      _ ->
        case ProjectBinding.read_effective(project_root) do
          {:ok, binding, mode} ->
            case AttachedAgentSync.sync(binding, project_root, mode: mode) do
              {:ok, _binding, changes} ->
                %{
                  "status" => "applied",
                  "changes" => changes,
                  "synced_count" => Enum.count(changes, &(&1["status"] == "synced"))
                }

              {:error, reason} ->
                %{"status" => "error", "message" => format_reason(reason)}
            end

          {:error, :not_found} ->
            %{"status" => "noop", "message" => "No governed project binding found."}

          {:error, reason} ->
            %{"status" => "error", "message" => format_reason(reason)}
        end
    end
  end

  defp fetch_latest_release(http_get, opts) do
    repo = Keyword.get(opts, :repository, repository())

    with {:ok, %{"tag_name" => tag_name, "html_url" => html_url}} <-
           http_get.("https://api.github.com/repos/#{repo}/releases/latest") do
      {:ok,
       %{
         "status" => "ok",
         "version" => normalize_version(tag_name),
         "url" => html_url
       }}
    end
  end

  defp detect_install_channel(executable_path, cmd_runner) do
    channel =
      cond do
        brew_install?(executable_path, cmd_runner) -> "brew"
        npm_install?(executable_path) -> "npm"
        direct_binary_install?(executable_path) -> "github_release_binary"
        true -> "unknown"
      end

    %{
      "channel" => channel,
      "executable_path" => executable_path,
      "writable" =>
        executable_path && File.regular?(executable_path) &&
          File.stat!(executable_path).access in [:read_write, :write]
    }
  rescue
    _ ->
      %{
        "channel" => "unknown",
        "executable_path" => executable_path,
        "writable" => false
      }
  end

  defp brew_install?(nil, _cmd_runner), do: false

  defp brew_install?(path, cmd_runner) do
    case cmd_runner.("brew", ["--prefix"], stderr_to_stdout: true) do
      {prefix, 0} ->
        path = Path.expand(path)
        prefix = prefix |> String.trim() |> Path.expand()
        String.starts_with?(path, prefix)

      _ ->
        false
    end
  end

  defp npm_install?(nil), do: false

  defp npm_install?(path) do
    case File.read(path) do
      {:ok, contents} ->
        String.contains?(contents, "@aryaminus/controlkeel") or
          String.contains?(contents, "vendor/controlkeel")

      {:error, _} ->
        false
    end
  end

  defp direct_binary_install?(nil), do: false

  defp direct_binary_install?(path) do
    case :os.type() do
      {:win32, _} ->
        String.ends_with?(String.downcase(path), "controlkeel.exe")

      _ ->
        Path.basename(path) == "controlkeel"
    end
  end

  defp attached_status(project_root, current_version) do
    case ProjectBinding.read_effective(project_root) do
      {:ok, binding, mode} ->
        agents =
          binding
          |> Map.get("attached_agents", %{})
          |> Enum.map(fn {agent, attrs} ->
            attrs = Enum.into(attrs, %{}, fn {k, v} -> {to_string(k), v} end)

            %{
              "agent" => agent,
              "controlkeel_version" => attrs["controlkeel_version"],
              "stale" => attrs["controlkeel_version"] != current_version,
              "scope" => attrs["scope"],
              "target" => attrs["target"]
            }
          end)

        %{
          "binding_present" => true,
          "binding_mode" => Atom.to_string(mode),
          "installed_count" => length(agents),
          "stale_count" => Enum.count(agents, & &1["stale"]),
          "agents" => agents
        }

      {:error, _} ->
        %{
          "binding_present" => false,
          "binding_mode" => nil,
          "installed_count" => 0,
          "stale_count" => 0,
          "agents" => []
        }
    end
  end

  defp recommended_commands(install, current_version, latest, attached) do
    latest_version = latest["version"]
    newer? = update_available?(current_version, latest_version)

    %{
      "self_update" => recommended_self_update_command(install["channel"], newer?),
      "attached_sync" =>
        if(attached["stale_count"] > 0,
          do: "controlkeel update --sync-attached",
          else: nil
        )
    }
  end

  defp recommended_self_update_command(_channel, false), do: nil
  defp recommended_self_update_command("brew", true), do: "brew upgrade controlkeel"
  defp recommended_self_update_command("npm", true), do: "npm i -g @aryaminus/controlkeel@latest"

  defp recommended_self_update_command("github_release_binary", true),
    do: "curl -fsSL https://github.com/#{repository()}/releases/latest/download/install.sh | sh"

  defp recommended_self_update_command(_, true), do: nil

  defp update_available?(current, latest) when is_binary(current) and is_binary(latest) do
    case {Version.parse(normalize_version(current)), Version.parse(normalize_version(latest))} do
      {{:ok, current_v}, {:ok, latest_v}} -> Version.compare(current_v, latest_v) == :lt
      _ -> false
    end
  end

  defp update_available?(_, _), do: false

  defp download_release_binary(version, opts) do
    asset = asset_name()

    url =
      "https://github.com/#{Keyword.get(opts, :repository, repository())}/releases/download/v#{version}/#{asset}"

    destination = Path.join(System.tmp_dir!(), "#{asset}-#{System.unique_integer([:positive])}")

    req =
      Req.new(
        url: url,
        headers: [{"user-agent", "controlkeel-update"}],
        receive_timeout: 30_000,
        into: File.stream!(destination, [:write, :binary])
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, destination}

      {:ok, %Req.Response{status: status}} ->
        {:error, "download failed with HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp default_http_get(url) do
    req =
      Req.new(
        url: url,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"user-agent", "controlkeel-update"}
        ],
        receive_timeout: 15_000
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, "HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp default_cmd(cmd, args, opts), do: System.cmd(cmd, args, opts)

  defp asset_name do
    case {os_name(), arch_name()} do
      {"linux", "x86_64"} -> "controlkeel-linux-x86_64"
      {"linux", "arm64"} -> "controlkeel-linux-arm64"
      {"macos", "x86_64"} -> "controlkeel-macos-x86_64"
      {"macos", "arm64"} -> "controlkeel-macos-arm64"
      {"windows", "x86_64"} -> "controlkeel-windows-x86_64.exe"
      other -> raise "unsupported platform for ControlKeel update: #{inspect(other)}"
    end
  end

  defp os_name do
    case :os.type() do
      {:unix, :darwin} -> "macos"
      {:unix, :linux} -> "linux"
      {:win32, _} -> "windows"
      other -> raise "unsupported operating system: #{inspect(other)}"
    end
  end

  defp arch_name do
    arch = :erlang.system_info(:system_architecture) |> to_string() |> String.downcase()

    cond do
      String.contains?(arch, "x86_64") or String.contains?(arch, "amd64") -> "x86_64"
      String.contains?(arch, "aarch64") or String.contains?(arch, "arm64") -> "arm64"
      true -> raise "unsupported architecture: #{arch}"
    end
  end

  defp release_page_url(opts \\ []) do
    "https://github.com/#{Keyword.get(opts, :repository, repository())}/releases/latest"
  end

  defp repository do
    System.get_env("CONTROLKEEL_GITHUB_REPO") || @repository
  end

  defp normalize_version("v" <> rest), do: rest
  defp normalize_version(version) when is_binary(version), do: String.trim(version)
  defp normalize_version(version), do: to_string(version)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
end
