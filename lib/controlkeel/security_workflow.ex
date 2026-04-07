defmodule ControlKeel.SecurityWorkflow do
  @moduledoc false

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Mission.Session
  alias ControlKeel.Platform.ServiceAccount

  @domain_pack "security"
  @security_occupations ~w(
    appsec_engineer
    security_researcher
    open_source_maintainer
    security_operations
  )
  @phases ~w(discovery triage reproduction patch validation disclosure)
  @artifact_types ~w(source diff repro_steps binary_report telemetry_rule disclosure_text)
  @target_scopes ~w(owned_repo owned_binary authorized_third_party unknown)
  @cyber_access_modes ~w(standard defensive_security verified_research)
  @evidence_types ~w(source diff runtime binary_report telemetry dependency)
  @exploitability_statuses ~w(suspected reproduced validated deferred)
  @patch_statuses ~w(none drafted validated merged)
  @disclosure_statuses ~w(draft triaged reported patched public wont_fix)
  @maintainer_scopes ~w(first_party open_source third_party_vendor)
  @sensitive_disclosure_patterns [
    ~r/proof[- ]of[- ]concept/i,
    ~r/\bexploit\b/i,
    ~r/\bshellcode\b/i,
    ~r/\bcurl\b.{0,80}(?:bash|sh)/i,
    ~r/\breverse shell\b/i,
    ~r/\bprivilege escalation\b/i
  ]
  @exploit_chain_patterns [
    ~r/\bchain(?:ing)?\b.{0,40}\bvulnerab/i,
    ~r/\bprivilege escalation\b/i,
    ~r/\blateral movement\b/i,
    ~r/\bpersistence\b/i,
    ~r/\bremote code execution\b/i
  ]
  @validation_evidence_markers ["test", "validation", "proof", "evidence", "regression", "verify"]

  def domain_pack, do: @domain_pack
  def security_occupations, do: @security_occupations
  def phases, do: @phases
  def artifact_types, do: @artifact_types
  def target_scopes, do: @target_scopes
  def cyber_access_modes, do: @cyber_access_modes

  def security_domain?(%Session{} = session), do: security_domain?(session.execution_brief || %{})
  def security_domain?(%{"domain_pack" => @domain_pack}), do: true
  def security_domain?(%{domain_pack: @domain_pack}), do: true
  def security_domain?(@domain_pack), do: true
  def security_domain?(_other), do: false

  def security_occupation?(occupation) when is_binary(occupation),
    do: occupation in @security_occupations

  def security_occupation?(_occupation), do: false

  def default_cyber_access_mode("security_researcher"), do: "verified_research"

  def default_cyber_access_mode(occupation) when occupation in @security_occupations,
    do: "defensive_security"

  def default_cyber_access_mode(_occupation), do: "standard"

  def normalize_cyber_access_mode(mode, default \\ "standard")

  def normalize_cyber_access_mode(mode, default) when is_binary(mode) do
    value = String.trim(mode)
    if value in @cyber_access_modes, do: value, else: default
  end

  def normalize_cyber_access_mode(_mode, default), do: default

  def session_cyber_access_mode(%Session{} = session) do
    metadata_mode =
      session.metadata
      |> Map.get("cyber_access_mode")
      |> normalize_cyber_access_mode(nil)

    cond do
      is_binary(metadata_mode) ->
        metadata_mode

      security_domain?(session) ->
        (session.execution_brief || %{})
        |> Map.get("occupation")
        |> normalize_security_occupation()
        |> default_cyber_access_mode()

      true ->
        "standard"
    end
  end

  def service_account_cyber_access_mode(%ServiceAccount{} = service_account) do
    service_account.metadata
    |> Map.get("cyber_access_mode")
    |> normalize_cyber_access_mode("standard")
  end

  def security_validation_requested?(input) when is_map(input) do
    security_domain?(input) or
      Map.get(input, "security_workflow_phase") in @phases or
      Map.get(input, "artifact_type") in @artifact_types or
      Map.get(input, "target_scope") in @target_scopes
  end

  def reproduction_like?(phase, artifact_type) do
    phase == "reproduction" or artifact_type == "repro_steps"
  end

  def sensitive_disclosure?(content) when is_binary(content) do
    Enum.any?(@sensitive_disclosure_patterns, &Regex.match?(&1, content))
  end

  def sensitive_disclosure?(_content), do: false

  def exploit_chain_indicators?(content) when is_binary(content) do
    Enum.any?(@exploit_chain_patterns, &Regex.match?(&1, content))
  end

  def exploit_chain_indicators?(_content), do: false

  def validation_evidence_present?(content) when is_binary(content) do
    lowered = String.downcase(content)
    Enum.any?(@validation_evidence_markers, &String.contains?(lowered, &1))
  end

  def validation_evidence_present?(_content), do: false

  def vulnerability_case?(finding) when is_map(finding) do
    metadata = Map.get(finding, :metadata) || Map.get(finding, "metadata") || %{}
    category = Map.get(finding, :category) || Map.get(finding, "category")

    category == "security" and normalized_finding_family(metadata) == "vulnerability_case"
  end

  def ensure_vulnerability_metadata(metadata, attrs \\ %{})
      when is_map(metadata) and is_map(attrs) do
    normalized = stringify_keys(metadata)
    attrs = stringify_keys(attrs)

    normalized
    |> Map.put("finding_family", "vulnerability_case")
    |> Map.put(
      "affected_component",
      normalized["affected_component"] || attrs["affected_component"] || "unspecified"
    )
    |> Map.put(
      "evidence_type",
      normalize_enum(
        normalized["evidence_type"] || attrs["evidence_type"],
        @evidence_types,
        "source"
      )
    )
    |> Map.put(
      "exploitability_status",
      normalize_enum(
        normalized["exploitability_status"] || attrs["exploitability_status"],
        @exploitability_statuses,
        "suspected"
      )
    )
    |> Map.put(
      "patch_status",
      normalize_enum(normalized["patch_status"] || attrs["patch_status"], @patch_statuses, "none")
    )
    |> Map.put(
      "disclosure_status",
      normalize_enum(
        normalized["disclosure_status"] || attrs["disclosure_status"],
        @disclosure_statuses,
        "draft"
      )
    )
    |> Map.put("cwe_ids", normalize_string_list(normalized["cwe_ids"] || attrs["cwe_ids"]))
    |> maybe_put_string("cve_id", normalized["cve_id"] || attrs["cve_id"])
    |> Map.put(
      "maintainer_scope",
      normalize_enum(
        normalized["maintainer_scope"] || attrs["maintainer_scope"],
        @maintainer_scopes,
        "first_party"
      )
    )
    |> maybe_put_string(
      "repro_artifact_ref",
      normalized["repro_artifact_ref"] || attrs["repro_artifact_ref"]
    )
    |> maybe_put_string(
      "patch_artifact_ref",
      normalized["patch_artifact_ref"] || attrs["patch_artifact_ref"]
    )
    |> maybe_put_string(
      "disclosure_due_at",
      normalized["disclosure_due_at"] || attrs["disclosure_due_at"]
    )
  end

  def vulnerability_case_summary(finding) when is_map(finding) do
    metadata =
      finding
      |> Map.get(:metadata, Map.get(finding, "metadata", %{}))
      |> ensure_vulnerability_metadata()

    %{
      "finding_family" => "vulnerability_case",
      "affected_component" => metadata["affected_component"],
      "evidence_type" => metadata["evidence_type"],
      "exploitability_status" => metadata["exploitability_status"],
      "patch_status" => metadata["patch_status"],
      "disclosure_status" => metadata["disclosure_status"],
      "cwe_ids" => metadata["cwe_ids"],
      "cve_id" => metadata["cve_id"],
      "maintainer_scope" => metadata["maintainer_scope"],
      "repro_artifact_ref" => metadata["repro_artifact_ref"],
      "patch_artifact_ref" => metadata["patch_artifact_ref"],
      "disclosure_due_at" => metadata["disclosure_due_at"],
      "sensitive_artifacts_redacted" => true
    }
  end

  def proof_summary(findings) when is_list(findings) do
    vulnerability_findings =
      Enum.filter(findings, &vulnerability_case?/1)

    cases =
      vulnerability_findings
      |> Enum.map(&case_proof_entry/1)

    %{
      "case_count" => length(cases),
      "unresolved" => Enum.count(cases, &(&1["release_gate_decision"] == "blocked")),
      "critical_unresolved" => Enum.count(vulnerability_findings, &security_release_blocker?(&1)),
      "cases" => cases
    }
  end

  def unresolved_release_risk?(finding) when is_map(finding) do
    metadata =
      finding
      |> Map.get(:metadata, Map.get(finding, "metadata", %{}))
      |> ensure_vulnerability_metadata()

    unresolved_patch? = metadata["patch_status"] not in ["validated", "merged"]
    unresolved_disclosure? = metadata["disclosure_status"] in ["draft", "triaged", "reported"]

    unresolved_patch? or unresolved_disclosure?
  end

  def security_release_blocker?(finding) when is_map(finding) do
    severity = Map.get(finding, :severity) || Map.get(finding, "severity")
    status = Map.get(finding, :status) || Map.get(finding, "status")

    vulnerability_case?(finding) and
      severity == "critical" and
      status in ["open", "blocked", "escalated"] and
      unresolved_release_risk?(finding)
  end

  def task_requires_verified_research?(task) when is_map(task) do
    metadata = Map.get(task, :metadata) || Map.get(task, "metadata") || %{}
    metadata["security_workflow_phase"] == "reproduction"
  end

  def isolated_runtime_required?(task) when is_map(task) do
    metadata = Map.get(task, :metadata) || Map.get(task, "metadata") || %{}
    truthy?(metadata["requires_isolated_runtime"])
  end

  def isolated_runtime_path?(claim_metadata) when is_map(claim_metadata) do
    Map.get(claim_metadata, "executor_mode") == "runtime"
  end

  defp case_proof_entry(finding) do
    metadata =
      finding
      |> Map.get(:metadata, Map.get(finding, "metadata", %{}))
      |> ensure_vulnerability_metadata()

    %{
      "title" => Map.get(finding, :title) || Map.get(finding, "title"),
      "severity" => Map.get(finding, :severity) || Map.get(finding, "severity"),
      "affected_component" => metadata["affected_component"],
      "evidence_type" => metadata["evidence_type"],
      "exploitability_status" => metadata["exploitability_status"],
      "patch_status" => metadata["patch_status"],
      "disclosure_status" => metadata["disclosure_status"],
      "validation_evidence" => metadata["patch_artifact_ref"],
      "release_gate_decision" =>
        if(unresolved_release_risk?(finding), do: "blocked", else: "ready"),
      "sensitive_content_redacted" => true
    }
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_security_occupation(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed in @security_occupations ->
        trimmed

      true ->
        case Enum.find(Domains.occupation_profiles(), &(&1.label == trimmed)) do
          %{id: id} when id in @security_occupations -> id
          _ -> trimmed
        end
    end
  end

  defp normalize_security_occupation(value), do: value

  defp normalize_enum(value, allowed, default) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in allowed, do: trimmed, else: default
  end

  defp normalize_enum(_value, _allowed, default), do: default

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_string_list(_value), do: []

  defp maybe_put_string(map, _key, nil), do: map

  defp maybe_put_string(map, key, value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: map, else: Map.put(map, key, trimmed)
  end

  defp maybe_put_string(map, key, value), do: Map.put(map, key, value)

  defp normalized_finding_family(metadata) when is_map(metadata) do
    metadata
    |> Map.get("finding_family", Map.get(metadata, :finding_family))
    |> case do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1", "yes"]
end
