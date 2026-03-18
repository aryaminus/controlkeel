defmodule ControlKeel.MCP.Tools.CkValidate do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.FastPath

  @allowed_kinds ~w(code config shell text)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      result = FastPath.scan(normalized)
      maybe_persist(normalized, result.findings)
      {:ok, public_result(result)}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    content = Map.get(arguments, "content")
    kind = Map.get(arguments, "kind", "code")

    cond do
      not is_binary(content) or String.trim(content) == "" ->
        {:error, {:invalid_arguments, "`content` is required and must be a non-empty string"}}

      kind not in @allowed_kinds ->
        {:error, {:invalid_arguments, "`kind` must be one of code, config, shell, or text"}}

      true ->
        with {:ok, session_id} <- normalize_optional_integer(arguments, "session_id"),
             {:ok, task_id} <- normalize_optional_integer(arguments, "task_id") do
          {:ok,
           %{
             "content" => content,
             "path" => optional_binary(arguments, "path"),
             "kind" => kind,
             "session_id" => session_id,
             "task_id" => task_id
           }}
        end
    end
  end

  defp normalize_optional_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
        end
    end
  end

  defp maybe_persist(%{"session_id" => nil}, _findings), do: :ok
  defp maybe_persist(%{"session_id" => _session_id}, []), do: :ok

  defp maybe_persist(
         %{"session_id" => session_id, "path" => path, "kind" => kind, "task_id" => task_id},
         findings
       ) do
    _ =
      Mission.record_runtime_findings(session_id, findings,
        session_id: session_id,
        task_id: task_id,
        path: path,
        kind: kind
      )

    :ok
  end

  defp public_result(%Scanner.Result{} = result) do
    %{
      "allowed" => result.allowed,
      "decision" => result.decision,
      "summary" => result.summary,
      "findings" => Enum.map(result.findings, &finding_to_map/1),
      "scanned_at" => result.scanned_at
    }
  end

  defp finding_to_map(%Scanner.Finding{} = finding) do
    %{
      "id" => finding.id,
      "severity" => finding.severity,
      "category" => finding.category,
      "rule_id" => finding.rule_id,
      "decision" => finding.decision,
      "plain_message" => finding.plain_message,
      "location" => finding.location,
      "metadata" => finding.metadata
    }
  end

  defp optional_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
