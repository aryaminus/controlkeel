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
  @kind_aliases %{
    "bash" => "shell",
    "command" => "shell",
    "commands" => "shell",
    "script" => "shell",
    "configuration" => "config",
    "file" => "config",
    "message" => "text",
    "context" => "text",
    "source" => "text",
    "instruction" => "text",
    "data" => "text",
    "review" => "text"
  }
  @intended_use_aliases %{
    "audit" => "context",
    "analysis" => "context",
    "analyze" => "context",
    "inspect" => "context",
    "inspection" => "context",
    "research" => "context",
    "read only" => "context",
    "readonly" => "context",
    "review" => "review"
  }
  @capability_aliases %{
    "file read" => "file_read",
    "file write" => "file_write",
    "read" => "file_read",
    "repo read" => "file_read",
    "read only" => "file_read",
    "readonly" => "file_read",
    "write" => "file_write",
    "shell" => "bash",
    "web" => "browser"
  }
  @workflow_phase_aliases %{
    "preflight" => "discovery",
    "analysis" => "discovery",
    "pre_edit" => "patch",
    "pre edit" => "patch",
    "preedit" => "patch",
    "post_edit" => "validation",
    "post edit" => "validation",
    "postedit" => "validation"
  }
  @target_scope_aliases %{
    "repo" => "owned_repo",
    "project" => "owned_repo",
    "workspace" => "owned_repo",
    "binary" => "owned_binary",
    "executable" => "owned_binary",
    "third party" => "authorized_third_party"
  }

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

    kind =
      arguments
      |> Map.get("kind", "code")
      |> normalize_kind()

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
               normalize_optional_intended_use(arguments),
             {:ok, requested_capabilities} <-
               normalize_optional_capabilities(arguments, "requested_capabilities"),
             {:ok, security_workflow_phase} <-
               normalize_optional_enum(
                 normalize_enum_alias(
                   arguments,
                   "security_workflow_phase",
                   @workflow_phase_aliases
                 ),
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
                 normalize_enum_alias(arguments, "target_scope", @target_scope_aliases),
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

  def workflow_phase_values do
    (SecurityWorkflow.phases() ++ Map.keys(@workflow_phase_aliases))
    |> Enum.uniq()
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

  defp normalize_optional_intended_use(arguments) do
    case Map.get(arguments, "intended_use") do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        normalized = normalize_intended_use(value)

        if normalized in TrustBoundary.intended_uses() do
          {:ok, normalized}
        else
          {:error,
           {:invalid_arguments,
            "`intended_use` must be one of #{Enum.join(TrustBoundary.intended_uses(), ", ")} if provided"}}
        end

      _ ->
        {:error,
         {:invalid_arguments,
          "`intended_use` must be one of #{Enum.join(TrustBoundary.intended_uses(), ", ")} if provided"}}
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
          |> Enum.map(&normalize_capability/1)

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

  defp normalize_enum_alias(arguments, key, aliases) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        Map.put(arguments, key, Map.get(aliases, normalize_token(value), value))

      _ ->
        arguments
    end
  end

  defp normalize_kind(value) when is_binary(value) do
    token = normalize_token(value)
    Map.get(@kind_aliases, token, token)
  end

  defp normalize_intended_use(value) when is_binary(value) do
    token = normalize_token(value)

    cond do
      token in TrustBoundary.intended_uses() ->
        token

      Map.has_key?(@intended_use_aliases, token) ->
        @intended_use_aliases[token]

      String.contains?(token, "review") ->
        "review"

      String.contains?(token, "audit") or String.contains?(token, "analysis") or
        String.contains?(token, "inspect") or String.contains?(token, "research") or
        String.contains?(token, "read only") or String.contains?(token, "readonly") ->
        "context"

      true ->
        value
    end
  end

  defp normalize_capability(value) when is_binary(value) do
    token = normalize_token(value)
    Map.get(@capability_aliases, token, token)
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[_-]+/, " ")
    |> String.replace(~r/\s+/, " ")
  end
end
