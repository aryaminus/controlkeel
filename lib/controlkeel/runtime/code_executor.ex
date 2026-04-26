defmodule ControlKeel.Runtime.CodeExecutor do
  @moduledoc """
  Guarded generated-code executor for MCP code-mode experiments.

  The executor is intentionally narrow: it refuses local host execution, denies
  network and secrets, validates source before execution, and only runs inside
  the Docker sandbox adapter for now.
  """

  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Runtime.CodeModePolicy

  @supported_languages ~w(javascript python)
  @max_code_bytes 64_000
  @max_output_bytes 65_536

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments),
         {:ok, validation} <- validate_source(normalized),
         {:ok, policy} <- enforce_policy(normalized),
         {:ok, execution} <- maybe_execute(normalized) do
      {:ok, result(normalized, policy, validation, execution)}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    code = Map.get(arguments, "code")
    language = arguments |> Map.get("language", "javascript") |> to_string() |> String.downcase()
    sandbox = arguments |> Map.get("sandbox", "docker") |> to_string() |> String.downcase()
    dry_run = Map.get(arguments, "dry_run", false) == true
    requested_capabilities = normalize_list(Map.get(arguments, "requested_capabilities", []))
    network_allowlist = normalize_list(Map.get(arguments, "network_allowlist", []))
    risk_tier = arguments |> Map.get("risk_tier", "medium") |> to_string()
    timeout_ms = normalize_int(Map.get(arguments, "timeout_ms"), 30_000)
    max_output_bytes = normalize_int(Map.get(arguments, "max_output_bytes"), @max_output_bytes)

    cond do
      not is_binary(code) or String.trim(code) == "" ->
        {:error, {:invalid_arguments, "`code` is required and must be a non-empty string"}}

      byte_size(code) > @max_code_bytes ->
        {:error, {:invalid_arguments, "`code` exceeds #{@max_code_bytes} bytes"}}

      language not in @supported_languages ->
        {:error,
         {:invalid_arguments,
          "`language` must be one of #{Enum.join(@supported_languages, ", ")}"}}

      timeout_ms > 60_000 ->
        {:error, {:invalid_arguments, "`timeout_ms` must be <= 60000"}}

      max_output_bytes > @max_output_bytes ->
        {:error, {:invalid_arguments, "`max_output_bytes` must be <= #{@max_output_bytes}"}}

      true ->
        {:ok,
         %{
           code: code,
           language: language,
           sandbox: sandbox,
           dry_run: dry_run,
           requested_capabilities: requested_capabilities,
           network_allowlist: network_allowlist,
           risk_tier: risk_tier,
           timeout_ms: timeout_ms,
           max_output_bytes: max_output_bytes,
           session_id: Map.get(arguments, "session_id"),
           task_id: Map.get(arguments, "task_id")
         }}
    end
  end

  defp validate_source(normalized) do
    case CkValidate.call(%{
           "content" => normalized.code,
           "kind" => "code",
           "path" => "generated://ck_execute_code/#{normalized.language}",
           "artifact_type" => "source",
           "intended_use" => "code",
           "source_type" => "generated",
           "trust_level" => "untrusted",
           "target_scope" => "owned_repo",
           "security_workflow_phase" => "pre_edit",
           "requested_capabilities" => normalized.requested_capabilities,
           "session_id" => normalized.session_id,
           "task_id" => normalized.task_id
         }) do
      {:ok, %{"decision" => decision} = validation} when decision in ["allow", "warn"] ->
        {:ok, validation}

      {:ok, validation} ->
        {:error, {:blocked, %{reason: "ck_validate_blocked", validation: validation}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enforce_policy(normalized) do
    policy =
      CodeModePolicy.build(
        risk_tier: normalized.risk_tier,
        requested_capabilities: normalized.requested_capabilities,
        network_allowlist: normalized.network_allowlist
      )

    cond do
      normalized.sandbox != "docker" ->
        {:error,
         {:blocked,
          %{
            reason: "sandbox_not_supported",
            message:
              "ck_execute_code only executes in the docker sandbox. Local host execution is intentionally blocked.",
            policy: policy
          }}}

      normalized.network_allowlist != [] or "network" in normalized.requested_capabilities ->
        {:error,
         {:blocked,
          %{
            reason: "network_not_supported",
            message:
              "ck_execute_code currently keeps network disabled even when an allowlist is supplied.",
            policy: policy
          }}}

      Enum.any?(
        normalized.requested_capabilities,
        &(&1 in ["filesystem", "secrets", "shell", "deploy"])
      ) ->
        {:error,
         {:blocked,
          %{
            reason: "capability_not_supported",
            message: "filesystem, secrets, shell, and deploy are denied for ck_execute_code.",
            policy: policy
          }}}

      true ->
        {:ok, policy}
    end
  end

  defp maybe_execute(%{dry_run: true} = normalized) do
    {:ok, %{dry_run: true, exit_status: nil, output: "", command: command_preview(normalized)}}
  end

  defp maybe_execute(normalized) do
    unless ControlKeel.ExecutionSandbox.Docker.available?() do
      {:error,
       {:blocked,
        %{
          reason: "docker_unavailable",
          message:
            "Docker is required for ck_execute_code execution. Re-run with dry_run=true or configure Docker."
        }}}
    else
      {command, args} = command_for(normalized)

      case ExecutionSandbox.run(command, args,
             sandbox: "docker",
             timeout: div(normalized.timeout_ms, 1000)
           ) do
        {:ok, %{output: output, exit_status: status}} ->
          {:ok,
           %{
             dry_run: false,
             exit_status: status,
             output: truncate(output, normalized.max_output_bytes),
             output_truncated: byte_size(output || "") > normalized.max_output_bytes,
             command: command_preview(normalized)
           }}

        {:error, reason} ->
          {:error, {:execution_failed, reason}}
      end
    end
  end

  defp command_for(%{language: "javascript", code: code, timeout_ms: timeout_ms}) do
    {"timeout", [timeout_seconds(timeout_ms), "node", "-e", code]}
  end

  defp command_for(%{language: "python", code: code, timeout_ms: timeout_ms}) do
    {"timeout", [timeout_seconds(timeout_ms), "python3", "-c", code]}
  end

  defp command_preview(%{language: language, timeout_ms: timeout_ms}) do
    runtime =
      if language == "javascript", do: "node -e <generated>", else: "python3 -c <generated>"

    "docker sandbox: timeout #{timeout_seconds(timeout_ms)} #{runtime}"
  end

  defp result(normalized, policy, validation, execution) do
    %{
      "allowed" => true,
      "language" => normalized.language,
      "sandbox" => normalized.sandbox,
      "dry_run" => execution.dry_run,
      "exit_status" => execution.exit_status,
      "output" => execution.output,
      "output_truncated" => Map.get(execution, :output_truncated, false),
      "command" => execution.command,
      "policy" => policy,
      "validation" => validation,
      "proof_artifacts" => policy["proof_artifacts"]
    }
  end

  defp timeout_seconds(ms), do: ms |> div(1000) |> max(1) |> Integer.to_string()

  defp truncate(nil, _limit), do: ""
  defp truncate(output, limit) when byte_size(output) <= limit, do: output
  defp truncate(output, limit), do: binary_part(output, 0, limit)

  defp normalize_int(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_int(_value, default), do: default

  defp normalize_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value) when is_binary(value), do: normalize_list([value])
  defp normalize_list(_value), do: []
end
