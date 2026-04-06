defmodule ControlKeel.SetupAdvisor do
  @moduledoc false

  alias ControlKeel.AgentExecution
  alias ControlKeel.AgentIntegration
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ProtocolInterop
  alias ControlKeel.ProviderBroker

  @preferred_attach_order [
    "opencode",
    "claude-code",
    "codex-cli",
    "cursor",
    "windsurf",
    "cline",
    "augment",
    "amp",
    "continue",
    "goose",
    "gemini-cli",
    "kiro",
    "pi",
    "roo-code",
    "aider",
    "copilot",
    "vscode"
  ]

  @core_loop "ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate"

  def snapshot(project_root \\ File.cwd!()) do
    root = ProjectRoot.resolve(project_root)
    agents = AgentExecution.list_agents(root)
    detected_hosts = detect_hosts(agents)

    %{
      "project_root" => root,
      "bootstrap" => ProjectBinding.bootstrap_summary(root),
      "provider_status" => ProviderBroker.status(root),
      "agents" => agents,
      "detected_hosts" => detected_hosts,
      "recommended_attach" => recommended_attach(detected_hosts, agents),
      "runtime_exports" => AgentIntegration.runtime_export_catalog(),
      "core_loop" => @core_loop
    }
  end

  def core_loop, do: @core_loop

  def detected_hosts_line(snapshot) do
    labels =
      snapshot["detected_hosts"]
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    if labels == "", do: "Detected hosts: none.", else: "Detected hosts: #{labels}."
  end

  def recommended_attach_lines(snapshot) do
    attach_lines =
      case snapshot["recommended_attach"] || [] do
        [] ->
          [
            "Attach next: controlkeel attach opencode",
            "Attach alternative: controlkeel attach codex-cli --scope project"
          ]

        [first | rest] ->
          [
            "Attach next: controlkeel attach #{first.id}"
            | Enum.map(rest, &"Attach alternative: controlkeel attach #{&1.id}")
          ]
      end

    attach_lines ++
      [
        "Runtime export: controlkeel runtime export open-swe",
        "Runtime export: controlkeel runtime export devin"
      ]
  end

  def service_account_hint(snapshot) do
    case ProjectBinding.read_effective(snapshot["project_root"]) do
      {:ok, binding, _mode} ->
        workspace_id = binding["workspace_id"]

        if is_integer(workspace_id) do
          "Hosted MCP: controlkeel service-account create --workspace-id #{workspace_id} --name runtime-mcp --scopes \"#{Enum.join(ProtocolInterop.hosted_mcp_scopes(), " ")}\""
        end

      _ ->
        nil
    end
  end

  def attached_agents_line(snapshot) do
    attached =
      snapshot["agents"]
      |> Enum.filter(& &1.attached)
      |> Enum.map(& &1.id)

    if attached == [],
      do: "Attached agents: none.",
      else: "Attached agents: #{Enum.join(attached, ", ")}."
  end

  defp recommended_attach(detected_hosts, agents) do
    attached_ids =
      agents
      |> Enum.filter(& &1.attached)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    detected_hosts
    |> Enum.reject(&MapSet.member?(attached_ids, &1.id))
    |> Enum.sort_by(&preferred_attach_index/1)
    |> Enum.take(3)
  end

  defp preferred_attach_index(%{id: id}) do
    Enum.find_index(@preferred_attach_order, &(&1 == id)) || 999
  end

  defp detect_hosts(agents) do
    agents_by_id = Map.new(agents, &{&1.id, &1})

    AgentIntegration.attach_catalog()
    |> Enum.reduce([], fn integration, acc ->
      presence = host_presence(integration.id, Map.get(agents_by_id, integration.id))

      if presence.reason do
        [
          %{
            id: integration.id,
            label: integration.label,
            reason: presence.reason,
            path: presence.path
          }
          | acc
        ]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp host_presence(_id, %{runnable: true, executable_path: path}) when is_binary(path) do
    %{reason: "command", path: path}
  end

  defp host_presence("codex-cli", %{executable_path: path}) when is_binary(path) do
    %{reason: "command", path: path}
  end

  defp host_presence("claude-code", _agent) do
    detect_directory(Path.join(user_home(), ".claude"), "workspace")
  end

  defp host_presence("cursor", _agent) do
    detect_directory(Path.dirname(cursor_mcp_config_path()), "config")
  end

  defp host_presence("windsurf", _agent) do
    detect_directory(Path.dirname(windsurf_mcp_config_path()), "config")
  end

  defp host_presence("kiro", _agent) do
    detect_directory(Path.join(user_home(), ".kiro"), "config")
  end

  defp host_presence("amp", _agent) do
    detect_directory(Path.join([user_home(), ".config", "amp"]), "config")
  end

  defp host_presence("augment", _agent) do
    detect_directory(Path.join(user_home(), ".augment"), "config")
  end

  defp host_presence("opencode", _agent) do
    detect_directory(Path.join([user_home(), ".config", "opencode"]), "config")
  end

  defp host_presence("gemini-cli", _agent) do
    detect_directory(Path.join([user_home(), ".gemini"]), "config")
  end

  defp host_presence("cline", _agent) do
    base = System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
    detect_directory(base, "config")
  end

  defp host_presence("goose", _agent) do
    detect_directory(Path.join([user_home(), ".config", "goose"]), "config")
  end

  defp host_presence("continue", _agent) do
    detect_directory(Path.join(user_home(), ".continue"), "config")
  end

  defp host_presence("pi", _agent) do
    detect_directory(Path.join(user_home(), ".pi"), "config")
  end

  defp host_presence(_id, %{executable_path: path}) when is_binary(path) do
    %{reason: "command", path: path}
  end

  defp host_presence(_id, _agent), do: %{reason: nil, path: nil}

  defp detect_directory(path, reason) do
    if File.dir?(path), do: %{reason: reason, path: path}, else: %{reason: nil, path: nil}
  end

  defp cursor_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([
          System.get_env("APPDATA") || home,
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      {:unix, :darwin} ->
        Path.join([
          home,
          "Library",
          "Application Support",
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      _ ->
        Path.join([home, ".config", "Cursor", "User", "globalStorage", "cursor.mcp.json"])
    end
  end

  defp windsurf_mcp_config_path do
    Path.join([user_home(), ".codeium", "windsurf", "mcp_config.json"])
  end

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end
end
