defmodule ControlKeel.CLI.Dispatch.SandboxSecurityCodeMode do
  @moduledoc false

  alias ControlKeel.CLI.Output
  alias ControlKeel.Governance.PreCommitHook
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Runtime.Paths
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :sandbox_status, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      adapters = ExecutionSandbox.supported_adapters()

      current_adapter_name = ExecutionSandbox.adapter_name([])

      current =
        Map.get(
          Enum.find(adapters, fn a -> a[:id] == current_adapter_name end) || %{},
          :name,
          "Unknown"
        )

      payload = %{
        "active" => current,
        "adapters" =>
          Enum.map(adapters, fn adapter ->
            %{
              "id" => adapter[:id],
              "name" => adapter[:name],
              "available" => !!adapter[:available]
            }
          end)
      }

      adapter_lines =
        Enum.map(adapters, fn adapter ->
          available = if adapter[:available], do: "available", else: "not available"
          marker = if adapter[:id] == ExecutionSandbox.adapter_name([]), do: " (active)", else: ""
          "  #{adapter[:name]} [#{adapter[:id]}]: #{available}#{marker}"
        end)

      Output.render_format(format, payload, fn _ ->
        [
          "Execution sandbox adapters:",
          "Active: #{current}"
        ] ++ adapter_lines
      end)
    end
  end

  # Back-compat: dispatch without options.
  def run_command(%{command: :sandbox_status} = parsed, root) do
    run_command(Map.put(parsed, :options, []), root)
  end

  def run_command(%{command: :sandbox_config, options: %{adapter: adapter}}, _project_root) do
    valid_adapters = Enum.map(ExecutionSandbox.supported_adapters(), & &1[:id])

    if adapter in valid_adapters do
      config_path = Paths.config_path()
      config = read_json_config(config_path)
      updated = Map.put(config, "execution_sandbox", adapter)

      File.mkdir_p!(Path.dirname(config_path))
      File.write!(config_path, Jason.encode!(updated, pretty: true) <> "\n")

      {:ok, ["Execution sandbox set to: #{adapter}", "Config written to: #{config_path}"]}
    else
      {:error,
       "Unknown sandbox adapter: #{adapter}. Valid adapters: #{Enum.join(valid_adapters, ", ")}"}
    end
  end

  def run_command(%{command: :precommit_check, options: options}, project_root) do
    root = options[:project_root] || project_root
    domain_pack = options[:domain_pack]
    enforce = options[:enforce] || false

    case PreCommitHook.check(root, domain_pack: domain_pack, enforce: enforce) do
      {:ok, result} ->
        staged_count = length(Map.get(result, :staged_files, []))

        case result.decision do
          "allow" ->
            {:ok, ["No policy violations found in #{staged_count} staged file(s)."]}

          "warn" ->
            lines =
              ["#{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:ok, lines}

          "block" ->
            lines =
              ["BLOCKED: #{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:error, Enum.join(lines, "\n")}
        end
    end
  end

  def run_command(%{command: :precommit_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    enforce = options[:enforce] || false

    case PreCommitHook.install(root, enforce: enforce) do
      {:ok, :installed} ->
        {:ok, ["Pre-commit hook installed in .git/hooks/pre-commit"]}

      {:ok, :updated} ->
        {:ok, ["Pre-commit hook updated in .git/hooks/pre-commit"]}

      {:error, :hook_exists} ->
        {:error, "A non-ControlKeel pre-commit hook already exists. Remove it first."}
    end
  end

  def run_command(%{command: :precommit_uninstall, options: options}, project_root) do
    root = options[:project_root] || project_root

    case PreCommitHook.uninstall(root) do
      {:ok, :uninstalled} ->
        {:ok, ["Pre-commit hook removed."]}

      {:ok, :not_controlkeel_hook} ->
        {:error, "Existing hook is not a ControlKeel hook."}

      {:ok, :no_hook_found} ->
        {:ok, ["No pre-commit hook found."]}
    end
  end
end
