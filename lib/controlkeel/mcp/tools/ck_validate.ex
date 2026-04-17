defmodule ControlKeel.MCP.Tools.CkValidate do
  @moduledoc false

  alias ControlKeel.AutoFix
  alias ControlKeel.Intent.Domains
  alias ControlKeel.Mission
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.FastPath
  alias ControlKeel.SecurityWorkflow
  alias ControlKeel.TrustBoundary

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
             {:ok, task_id} <- normalize_optional_integer(arguments, "task_id"),
             {:ok, domain_pack} <- normalize_optional_domain_pack(arguments),
             {:ok, source_type} <-
               normalize_optional_enum(arguments, "source_type", TrustBoundary.source_types()),
             {:ok, trust_level} <-
               normalize_optional_enum(arguments, "trust_level", TrustBoundary.trust_levels()),
             {:ok, intended_use} <-
               normalize_optional_enum(arguments, "intended_use", TrustBoundary.intended_uses()),
             {:ok, requested_capabilities} <-
               normalize_optional_capabilities(arguments, "requested_capabilities"),
             {:ok, security_workflow_phase} <-
               normalize_optional_enum(
                 arguments,
                 "security_workflow_phase",
                 SecurityWorkflow.phases()
               ),
             {:ok, artifact_type} <-
               normalize_optional_enum(
                 normalize_artifact_type_alias(arguments),
                 "artifact_type",
                 SecurityWorkflow.artifact_types()
               ),
             {:ok, target_scope} <-
               normalize_optional_enum(
                 arguments,
                 "target_scope",
                 SecurityWorkflow.target_scopes()
               ) do
          {:ok,
           %{
             "content" => content,
             "path" => optional_binary(arguments, "path"),
             "kind" => kind,
             "session_id" => session_id,
             "task_id" => task_id,
             "domain_pack" => domain_pack,
             "source_type" => source_type,
             "trust_level" => trust_level,
             "intended_use" => intended_use,
             "requested_capabilities" => requested_capabilities,
             "security_workflow_phase" => security_workflow_phase,
             "artifact_type" => artifact_type,
             "target_scope" => target_scope
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

  defp normalize_optional_domain_pack(arguments) do
    case Map.get(arguments, "domain_pack") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_binary(value) ->
        pack = Domains.normalize_pack(value, "__unsupported__")

        if Domains.supported_pack?(pack) do
          {:ok, pack}
        else
          {:error,
           {:invalid_arguments,
            "`domain_pack` must be one of #{Enum.join(Domains.supported_packs(), ", ")}"}}
        end
    end
  end

  defp maybe_persist(%{"session_id" => nil}, _findings), do: :ok
  defp maybe_persist(%{"session_id" => _session_id}, []), do: :ok

  defp maybe_persist(
         %{
           "session_id" => session_id,
           "path" => path,
           "kind" => kind,
           "task_id" => task_id,
           "domain_pack" => domain_pack,
           "security_workflow_phase" => security_workflow_phase,
           "artifact_type" => artifact_type,
           "target_scope" => target_scope
         },
         findings
       ) do
    _ =
      Mission.record_runtime_findings(session_id, findings,
        session_id: session_id,
        task_id: task_id,
        path: path,
        kind: kind,
        domain_pack: domain_pack,
        security_workflow_phase: security_workflow_phase,
        artifact_type: artifact_type,
        target_scope: target_scope
      )

    :ok
  end

  defp public_result(%Scanner.Result{} = result) do
    fix_prompts =
      result.findings
      |> Enum.filter(&(&1.decision == "block"))
      |> Enum.map(fn f ->
        fix = AutoFix.generate(f)

        %{
          "rule_id" => f.rule_id,
          "supported" => fix["supported"],
          "agent_prompt" => fix["agent_prompt"],
          "summary" => fix["summary"],
          "requires_human" => fix["requires_human"]
        }
      end)
      |> Enum.reject(&is_nil(&1["agent_prompt"]))

    %{
      "allowed" => result.allowed,
      "decision" => result.decision,
      "summary" => result.summary,
      "findings" => Enum.map(result.findings, &finding_to_map/1),
      "fix_prompts" => fix_prompts,
      "scanned_at" => result.scanned_at,
      "advisory" => result.advisory
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

  defp normalize_optional_enum(arguments, key, allowed) do
    case Map.get(arguments, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if value in allowed do
          {:ok, value}
        else
          {:error,
           {:invalid_arguments, "`#{key}` must be one of #{Enum.join(allowed, ", ")} if provided"}}
        end

      _ ->
        {:error,
         {:invalid_arguments, "`#{key}` must be one of #{Enum.join(allowed, ", ")} if provided"}}
    end
  end

  defp normalize_optional_capabilities(arguments, key) do
    case Map.get(arguments, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        normalized =
          values
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)

        invalid = Enum.reject(normalized, &(&1 in TrustBoundary.capabilities()))

        if invalid == [] do
          {:ok, Enum.uniq(normalized)}
        else
          {:error,
           {:invalid_arguments,
            "`#{key}` contains unsupported capability values: #{Enum.join(invalid, ", ")}"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` must be an array if provided"}}
    end
  end

  defp normalize_artifact_type_alias(arguments) do
    case Map.get(arguments, "artifact_type") do
      "instruction" -> Map.put(arguments, "artifact_type", "source")
      "text" -> Map.put(arguments, "artifact_type", "source")
      _ -> arguments
    end
  end
end
