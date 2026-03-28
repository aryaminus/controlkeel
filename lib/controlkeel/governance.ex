defmodule ControlKeel.Governance do
  @moduledoc false

  alias ControlKeel.Analytics
  alias ControlKeel.Distribution
  alias ControlKeel.Mission
  alias ControlKeel.Mission.ProofBundle
  alias ControlKeel.Scanner
  alias ControlKeel.Scanner.FastPath

  @config_extensions ~w(.conf .config .env .ini .json .lock .toml .xml .yaml .yml)
  @shell_extensions ~w(.bash .ps1 .sh .zsh)
  @text_extensions ~w(.csv .md .rst .text .txt)
  @install_files [
    ".github/workflows/controlkeel-pr-governor.yml",
    ".github/workflows/controlkeel-release-governor.yml",
    ".github/workflows/scorecards.yml",
    ".github/controlkeel/README.md"
  ]

  def review_diff(base_ref, head_ref, opts \\ [])
      when is_binary(base_ref) and is_binary(head_ref) do
    project_root = opts[:project_root] || File.cwd!()

    with {:ok, patch} <- git_diff(project_root, base_ref, head_ref),
         {:ok, review} <-
           review_patch(
             patch,
             opts
             |> Keyword.put(:mode, "diff")
             |> Keyword.put(:base_ref, base_ref)
             |> Keyword.put(:head_ref, head_ref)
             |> Keyword.put(:project_root, project_root)
           ) do
      {:ok,
       review
       |> Map.put("base_ref", base_ref)
       |> Map.put("head_ref", head_ref)
       |> Map.put("project_root", Path.expand(project_root))}
    end
  end

  def review_patch(patch, opts \\ []) when is_binary(patch) do
    fragments = parse_unified_diff(patch)
    session_id = normalize_integer(opts[:session_id])
    domain_pack = blank_to_nil(opts[:domain_pack])
    project_root = opts[:project_root] || File.cwd!()
    dependency_review = normalize_map(opts[:dependency_review])
    github = normalize_map(opts[:github])

    scan_findings =
      fragments
      |> Enum.flat_map(fn fragment ->
        fragment
        |> scan_fragment(session_id, domain_pack)
        |> Enum.map(&attach_fragment_metadata(&1, fragment))
      end)

    dependency_findings = dependency_review_findings(dependency_review)
    findings = scan_findings ++ dependency_findings
    decision = final_decision(findings)
    review_summary = review_summary(decision, findings, fragments)

    with {:ok, persisted_findings} <- persist_findings(session_id, findings, opts) do
      telemetry =
        record_review_event(
          session_id,
          opts[:mode] || "patch",
          decision,
          project_root,
          github,
          review_summary,
          opts
        )

      {:ok,
       %{
         "mode" => opts[:mode] || "patch",
         "summary" => review_summary.summary,
         "decision" => decision,
         "blocking" => decision == "block",
         "files_reviewed" => review_summary.files_reviewed,
         "chunks_reviewed" => review_summary.chunks_reviewed,
         "added_lines_reviewed" => review_summary.added_lines_reviewed,
         "finding_totals" => review_summary.finding_totals,
         "findings" => Enum.map(findings, &governance_finding_summary/1),
         "persisted_finding_ids" => Enum.map(persisted_findings, & &1.id),
         "telemetry" => telemetry
       }}
    end
  end

  def release_readiness(opts \\ [])

  def release_readiness(opts) when is_list(opts) do
    do_release_readiness(Enum.into(opts, %{}))
  end

  def release_readiness(opts) when is_map(opts), do: do_release_readiness(opts)

  def install_github_scaffolding(project_root, opts \\ []) when is_binary(project_root) do
    root = Path.expand(project_root)

    files = %{
      ".github/workflows/controlkeel-pr-governor.yml" => pr_governor_workflow(),
      ".github/workflows/controlkeel-release-governor.yml" => release_governor_workflow(),
      ".github/workflows/scorecards.yml" => scorecards_workflow(),
      ".github/controlkeel/README.md" => governance_readme(opts)
    }

    with :ok <- write_scaffold_files(root, files) do
      _ =
        Analytics.record(%{
          event: "governance_scaffold_installed",
          source: "governance",
          project_root: root,
          metadata: %{
            "provider" => "github",
            "files" => Map.keys(files)
          }
        })

      {:ok,
       %{
         "provider" => "github",
         "project_root" => root,
         "files" => Enum.map(@install_files, &Path.join(root, &1))
       }}
    end
  end

  defp do_release_readiness(opts) do
    session_id = normalize_integer(opts["session_id"] || opts[:session_id])

    case session_id && Mission.get_session_context(session_id) do
      nil ->
        {:error, "Release readiness requires a valid session_id."}

      session ->
        findings = session.findings || []
        blocking_findings = Enum.filter(findings, &blocking_release_finding?/1)
        open_findings = Enum.filter(findings, &(&1.status in ["open", "blocked", "escalated"]))
        latest_proof = latest_release_candidate_proof(session)
        smoke = normalize_map(opts["smoke"] || opts[:smoke])
        provenance = normalize_map(opts["provenance"] || opts[:provenance])
        smoke_ready? = smoke_ready?(smoke)
        provenance_verified? = provenance_verified?(provenance)
        deploy_ready? = latest_proof && latest_proof.deploy_ready

        reasons =
          []
          |> maybe_add_reason(
            blocking_findings != [],
            blocking_findings_reason(blocking_findings)
          )
          |> maybe_add_reason(
            open_findings != [] and blocking_findings == [],
            "#{length(open_findings)} unresolved finding(s) still need review."
          )
          |> maybe_add_reason(
            is_nil(latest_proof),
            "No proof bundle is available for release review."
          )
          |> maybe_add_reason(
            latest_proof && not latest_proof.deploy_ready,
            "The latest proof bundle is not deploy-ready."
          )
          |> maybe_add_reason(not smoke_ready?, "Release smoke evidence is missing or not green.")
          |> maybe_add_reason(
            not provenance_verified?,
            "Artifact provenance is missing or unverified."
          )

        status =
          cond do
            blocking_findings != [] ->
              "blocked"

            deploy_ready? and smoke_ready? and provenance_verified? and open_findings == [] ->
              "ready"

            true ->
              "needs-review"
          end

        summary =
          case status do
            "ready" -> "Release is backed by proof, smoke, and provenance evidence."
            "blocked" -> Enum.join(reasons, " ")
            _ -> Enum.join(reasons, " ")
          end

        telemetry =
          record_release_event(session, status, latest_proof, smoke, provenance, reasons, opts)

        {:ok,
         %{
           "status" => status,
           "summary" => summary,
           "session_id" => session.id,
           "session_title" => session.title,
           "sha" => blank_to_nil(opts["sha"] || opts[:sha]),
           "proof" => release_proof_summary(latest_proof),
           "findings" => %{
             "open" => Enum.count(open_findings, &(&1.status == "open")),
             "blocked" => Enum.count(open_findings, &(&1.status == "blocked")),
             "escalated" => Enum.count(open_findings, &(&1.status == "escalated")),
             "high_or_critical" =>
               Enum.count(open_findings, &(&1.severity in ["high", "critical"]))
           },
           "reasons" => reasons,
           "smoke" => release_evidence_summary(smoke, smoke_ready?),
           "provenance" => release_evidence_summary(provenance, provenance_verified?),
           "telemetry" => telemetry
         }}
    end
  end

  defp git_diff(project_root, base_ref, head_ref) do
    case System.cmd("git", ["diff", "--unified=0", base_ref, head_ref], cd: project_root) do
      {output, 0} ->
        {:ok, output}

      {output, _code} ->
        {:error, "Failed to compute git diff: #{String.trim(output)}"}
    end
  rescue
    error ->
      {:error, "Failed to compute git diff: #{Exception.message(error)}"}
  end

  defp parse_unified_diff(patch) do
    {state, current_fragment} =
      patch
      |> String.split("\n", trim: false)
      |> Enum.reduce({%{path: nil, current_line: nil, fragments: []}, nil}, fn line,
                                                                               {state, fragment} ->
        cond do
          String.starts_with?(line, "diff --git ") ->
            {flush_fragment(state, fragment), nil}

          String.starts_with?(line, "+++ ") ->
            {put_path(flush_fragment(state, fragment), parse_patch_path(line)), nil}

          String.starts_with?(line, "@@ ") ->
            {flush_fragment(state, fragment), start_fragment(line, state.path, nil)}

          String.starts_with?(line, "+") and not String.starts_with?(line, "+++") and fragment ->
            {state, append_added_line(fragment, String.trim_leading(line, "+"))}

          String.starts_with?(line, " ") and fragment ->
            {state, increment_fragment_line(fragment)}

          String.starts_with?(line, "-") and not String.starts_with?(line, "---") ->
            {state, fragment}

          true ->
            {state, fragment}
        end
      end)

    final_state = flush_fragment(state, current_fragment)
    Enum.reverse(final_state.fragments)
  end

  defp put_path(state, nil), do: %{state | path: nil}
  defp put_path(state, path), do: %{state | path: path}

  defp parse_patch_path("+++ " <> "/dev/null"), do: nil

  defp parse_patch_path("+++ " <> raw_path) do
    raw_path
    |> String.trim()
    |> String.trim_leading("b/")
    |> String.trim_leading("a/")
  end

  defp start_fragment(header, path, current_fragment) do
    parsed_start =
      case Regex.run(~r/@@ -\d+(?:,\d+)? \+(\d+)/, header) do
        [_, start] -> String.to_integer(start)
        _ -> 1
      end

    current_fragment
    |> case do
      nil -> %{}
      fragment -> fragment
    end
    |> Map.merge(%{
      path: path,
      kind: infer_kind(path),
      start_line: parsed_start,
      current_line: parsed_start,
      added_lines: []
    })
  end

  defp append_added_line(fragment, line) do
    %{
      fragment
      | added_lines: fragment.added_lines ++ [line],
        current_line: fragment.current_line + 1
    }
  end

  defp increment_fragment_line(fragment) do
    %{fragment | current_line: fragment.current_line + 1}
  end

  defp flush_fragment(state, nil), do: state

  defp flush_fragment(state, fragment) do
    if fragment.path && fragment.added_lines != [] do
      finalized = %{
        path: fragment.path,
        kind: fragment.kind,
        start_line: fragment.start_line,
        added_line_count: length(fragment.added_lines),
        content: Enum.join(fragment.added_lines, "\n")
      }

      %{state | fragments: [finalized | state.fragments]}
    else
      state
    end
  end

  defp infer_kind(nil), do: "text"

  defp infer_kind(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      ext in @config_extensions -> "config"
      ext in @shell_extensions -> "shell"
      ext in @text_extensions -> "text"
      true -> "code"
    end
  end

  defp scan_fragment(fragment, session_id, domain_pack) do
    fragment
    |> Map.take([:content, :path, :kind])
    |> Map.put(:session_id, session_id)
    |> Map.put(:domain_pack, domain_pack)
    |> FastPath.scan()
    |> Map.get(:findings, [])
  end

  defp attach_fragment_metadata(%Scanner.Finding{} = finding, fragment) do
    metadata =
      finding.metadata
      |> Map.put("chunk_start_line", fragment.start_line)
      |> Map.put("chunk_added_line_count", fragment.added_line_count)

    %Scanner.Finding{
      finding
      | location:
          Map.merge(finding.location || %{}, %{
            "path" => fragment.path,
            "kind" => fragment.kind
          }),
        metadata: metadata
    }
  end

  defp dependency_review_findings(review) when review == %{}, do: []

  defp dependency_review_findings(review) do
    issues =
      review["issues"] ||
        review["vulnerabilities"] ||
        review[:issues] ||
        review[:vulnerabilities] ||
        []

    Enum.map(List.wrap(issues), &dependency_issue_to_finding/1)
  end

  defp dependency_issue_to_finding(issue) do
    issue = normalize_map(issue)
    severity = normalize_dependency_severity(issue["severity"] || issue["risk"])
    path = blank_to_nil(issue["manifest_path"]) || "dependency-review"
    package = issue["package"] || issue["dependency"] || "Dependency"
    summary = issue["summary"] || issue["message"] || "Dependency review reported an issue."
    rule_id = issue["rule_id"] || "dependencies.review"
    decision = if severity in ["critical", "high"], do: "block", else: "warn"
    fingerprint = dependency_fingerprint(issue, rule_id)

    %Scanner.Finding{
      id: fingerprint,
      severity: severity,
      category: "dependencies",
      rule_id: rule_id,
      decision: decision,
      plain_message: "#{package}: #{summary}",
      location: %{"path" => path, "kind" => "config"},
      metadata:
        issue
        |> Map.put("scanner", "dependency_review")
        |> Map.put("package", package)
    }
  end

  defp dependency_fingerprint(issue, rule_id) do
    seed =
      [issue["package"], issue["manifest_path"], issue["summary"], issue["advisory_id"], rule_id]
      |> Enum.map(&to_string(blank_to_nil(&1) || ""))
      |> Enum.join(":")

    "dep_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp normalize_dependency_severity(nil), do: "medium"
  defp normalize_dependency_severity("moderate"), do: "medium"
  defp normalize_dependency_severity("info"), do: "low"
  defp normalize_dependency_severity(value), do: String.downcase(to_string(value))

  defp persist_findings(nil, _findings, _opts), do: {:ok, []}
  defp persist_findings(_session_id, [], _opts), do: {:ok, []}

  defp persist_findings(session_id, findings, opts) do
    Enum.reduce_while(findings, {:ok, []}, fn finding, {:ok, acc} ->
      result =
        Mission.record_runtime_findings(session_id, [finding],
          session_id: session_id,
          scanner: finding.metadata["scanner"] || "governance",
          source: opts[:source] || "governance_review",
          phase: opts[:phase] || "pre_merge",
          path: get_in(finding.location, ["path"]),
          kind: get_in(finding.location, ["kind"])
        )

      case result do
        {:ok, persisted} ->
          {:cont, {:ok, acc ++ persisted}}

        {:error, reason} ->
          {:halt, {:error, "Failed to persist review findings: #{inspect(reason)}"}}
      end
    end)
  end

  defp final_decision(findings) do
    decisions = Enum.map(findings, & &1.decision)

    cond do
      "block" in decisions -> "block"
      "warn" in decisions -> "warn"
      true -> "allow"
    end
  end

  defp review_summary(decision, findings, fragments) do
    files_reviewed = fragments |> Enum.map(& &1.path) |> Enum.uniq() |> length()
    chunks_reviewed = length(fragments)
    added_lines_reviewed = Enum.reduce(fragments, 0, &(&1.added_line_count + &2))

    finding_totals = %{
      "total" => length(findings),
      "critical" => Enum.count(findings, &(&1.severity == "critical")),
      "high" => Enum.count(findings, &(&1.severity == "high")),
      "medium" => Enum.count(findings, &(&1.severity == "medium")),
      "low" => Enum.count(findings, &(&1.severity == "low"))
    }

    summary =
      cond do
        findings == [] and chunks_reviewed == 0 ->
          "No added hunks were found in the supplied diff."

        findings == [] ->
          "Reviewed #{files_reviewed} file(s) across #{chunks_reviewed} added hunk(s); no issues detected."

        decision == "block" ->
          "Blocked #{length(findings)} finding(s) across #{files_reviewed} file(s)."

        true ->
          "Warnings detected in #{files_reviewed} file(s) across #{chunks_reviewed} added hunk(s)."
      end

    %{
      summary: summary,
      files_reviewed: files_reviewed,
      chunks_reviewed: chunks_reviewed,
      added_lines_reviewed: added_lines_reviewed,
      finding_totals: finding_totals
    }
  end

  defp governance_finding_summary(finding) do
    %{
      "id" => finding.id,
      "rule_id" => finding.rule_id,
      "category" => finding.category,
      "severity" => finding.severity,
      "decision" => finding.decision,
      "plain_message" => finding.plain_message,
      "path" => get_in(finding.location, ["path"]),
      "kind" => get_in(finding.location, ["kind"]),
      "metadata" => finding.metadata
    }
  end

  defp record_review_event(session_id, mode, decision, project_root, github, review_summary, opts) do
    session = session_id && Mission.get_session(session_id)

    metadata =
      github
      |> Map.put("mode", mode)
      |> Map.put("decision", decision)
      |> Map.put("summary", review_summary.summary)
      |> Map.put("files_reviewed", review_summary.files_reviewed)
      |> Map.put("chunks_reviewed", review_summary.chunks_reviewed)
      |> Map.put("finding_totals", review_summary.finding_totals)
      |> maybe_put("base_ref", opts[:base_ref])
      |> maybe_put("head_ref", opts[:head_ref])

    _ =
      Analytics.record(%{
        event: if(mode == "diff", do: "review_diff_executed", else: "review_pr_executed"),
        source: "governance",
        session_id: session_id,
        workspace_id: session && session.workspace_id,
        project_root: Path.expand(project_root),
        metadata: metadata
      })

    if github == %{}, do: nil, else: metadata
  end

  defp record_release_event(session, status, proof, smoke, provenance, reasons, opts) do
    github = normalize_map(opts["github"] || opts[:github])

    metadata =
      github
      |> Map.put("status", status)
      |> Map.put("sha", blank_to_nil(opts["sha"] || opts[:sha]))
      |> Map.put("proof_id", proof && proof.id)
      |> Map.put("deploy_ready", proof && proof.deploy_ready)
      |> Map.put("smoke", release_evidence_summary(smoke, smoke_ready?(smoke)))
      |> Map.put(
        "provenance",
        release_evidence_summary(provenance, provenance_verified?(provenance))
      )
      |> Map.put("reasons", reasons)

    _ =
      Analytics.record(%{
        event: "release_readiness_checked",
        source: "governance",
        session_id: session.id,
        workspace_id: session.workspace_id,
        metadata: metadata
      })

    if github == %{}, do: nil, else: metadata
  end

  defp latest_release_candidate_proof(session) do
    latest_by_task = Mission.latest_proof_bundles_for_session(session.id)

    release_task_ids =
      session.tasks
      |> Enum.filter(&(get_in(&1.metadata || %{}, ["track"]) == "release"))
      |> Enum.map(& &1.id)

    candidate_proofs =
      if release_task_ids == [] do
        Map.values(latest_by_task)
      else
        latest_by_task
        |> Map.take(release_task_ids)
        |> Map.values()
      end

    Enum.max_by(candidate_proofs, &proof_sort_key/1, fn -> nil end)
  end

  defp proof_sort_key(%ProofBundle{} = proof) do
    {proof.version || 0, proof.generated_at || proof.inserted_at, proof.id || 0}
  end

  defp release_proof_summary(nil), do: nil

  defp release_proof_summary(proof) do
    %{
      "id" => proof.id,
      "task_id" => proof.task_id,
      "version" => proof.version,
      "status" => proof.status,
      "risk_score" => proof.risk_score,
      "deploy_ready" => proof.deploy_ready,
      "generated_at" => proof.generated_at
    }
  end

  defp blocking_release_finding?(finding) do
    finding.status in ["blocked", "escalated"] or
      (finding.status == "open" and finding.severity in ["high", "critical"])
  end

  defp blocking_findings_reason(findings) do
    "#{length(findings)} blocking finding(s) remain unresolved."
  end

  defp smoke_ready?(%{"ready" => value}), do: truthy?(value)

  defp smoke_ready?(evidence) do
    status = evidence["status"] || evidence["conclusion"]
    truthy?(evidence["success"]) or status in ["success", "passed", "green"]
  end

  defp provenance_verified?(%{"verified" => value}), do: truthy?(value)

  defp provenance_verified?(evidence) do
    truthy?(evidence["attested"]) or truthy?(evidence["verified"]) or
      (evidence["status"] || evidence["conclusion"]) in ["success", "verified", "attested"]
  end

  defp release_evidence_summary(evidence, satisfied?) do
    evidence
    |> Map.take(["run_id", "status", "conclusion", "artifact_source", "attestation_id"])
    |> Map.put("satisfied", satisfied?)
  end

  defp write_scaffold_files(root, files) do
    Enum.reduce_while(files, :ok, fn {relative_path, content}, :ok ->
      path = Path.join(root, relative_path)

      case File.mkdir_p(Path.dirname(path)) do
        :ok ->
          case File.write(path, content) do
            :ok ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, "Failed to write #{relative_path}: #{inspect(reason)}"}}
          end

        {:error, reason} ->
          {:halt, {:error, "Failed to create #{relative_path}: #{inspect(reason)}"}}
      end
    end)
  end

  defp pr_governor_workflow do
    """
    name: ControlKeel PR Governor

    on:
      pull_request:
      workflow_dispatch:

    permissions:
      contents: read
      pull-requests: read
      security-events: write

    jobs:
      dependency-review:
        if: github.event_name == 'pull_request'
        runs-on: ubuntu-latest
        steps:
          - uses: actions/dependency-review-action@v4

      controlkeel-review:
        runs-on: ubuntu-latest
        needs: dependency-review
        if: always()
        steps:
          - uses: actions/checkout@v4
            with:
              fetch-depth: 0

          - name: Install ControlKeel
            run: curl -fsSL #{Distribution.latest_installer_url("sh")} | sh

          - name: Bootstrap governed repo
            run: controlkeel bootstrap --project-root . --ephemeral-ok

          - name: Prepare PR patch
            if: github.event_name == 'pull_request'
            run: |
              git fetch --no-tags --prune --depth=1 origin "${{ github.base_ref }}"
              git diff --unified=0 "origin/${{ github.base_ref }}" HEAD > controlkeel-review.patch

          - name: Run governed review
            if: github.event_name == 'pull_request'
            run: controlkeel review pr --patch controlkeel-review.patch --project-root .
    """
  end

  defp release_governor_workflow do
    """
    name: ControlKeel Release Governor

    on:
      workflow_dispatch:
      push:
        tags:
          - 'v*'

    permissions:
      contents: read
      attestations: write
      id-token: write

    jobs:
      release-readiness:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
            with:
              fetch-depth: 0

          - name: Install ControlKeel
            run: curl -fsSL #{Distribution.latest_installer_url("sh")} | sh

          - name: Bootstrap governed repo
            run: controlkeel bootstrap --project-root . --ephemeral-ok

          - name: Check governed release readiness
            run: |
              controlkeel release-ready \
                --project-root . \
                --sha "${{ github.sha }}" \
                --smoke-status success \
                --artifact-source github-actions \
                --provenance-verified

          - name: Attest release inputs
            uses: actions/attest-build-provenance@v2
            with:
              subject-path: .
    """
  end

  defp scorecards_workflow do
    """
    name: Scorecards

    on:
      branch_protection_rule:
      schedule:
        - cron: '19 5 * * 1'
      push:
        branches: ['main']

    permissions:
      security-events: write
      id-token: write
      contents: read
      actions: read

    jobs:
      analysis:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
            with:
              persist-credentials: false

          - uses: ossf/scorecard-action@v2.4.0
            with:
              results_file: results.sarif
              results_format: sarif
              publish_results: true

          - uses: github/codeql-action/upload-sarif@v3
            with:
              sarif_file: results.sarif
    """
  end

  defp governance_readme(_opts) do
    """
    # ControlKeel GitHub Governance

    These workflows keep ControlKeel in the repository-native path: no GitHub App is required.

    ## What gets installed

    - `controlkeel-pr-governor.yml` runs dependency review plus governed diff review before merge.
    - `controlkeel-release-governor.yml` checks release readiness against proof state, release smoke evidence, and artifact provenance.
    - `scorecards.yml` publishes an OpenSSF Scorecard SARIF report.

    ## Recommended branch protection

    Require these checks on `main`:

    - `ControlKeel PR Governor / controlkeel-review`
    - `ControlKeel Release Governor / release-readiness`
    - your existing CI status checks

    ## Optional GitHub hardening

    - Enable GitHub dependency review and secret scanning if your plan includes them.
    - Add a standard CodeQL workflow if the repository already relies on GitHub code scanning.
    - Keep artifact attestations turned on for release workflows.

    ## How this stays honest

    ControlKeel does not pretend to govern every merge path natively. When the repo is bootstrapped, these workflows call the same local commands the product exposes:

    - `controlkeel review diff`
    - `controlkeel review pr`
    - `controlkeel release-ready`
    """
  end

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_map(value) when is_map(value) do
    Enum.into(value, %{}, fn {key, nested} ->
      {to_string(key), if(is_map(nested), do: normalize_map(nested), else: nested)}
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp truthy?(value) when value in [true, "true", "1", 1, "yes"], do: true
  defp truthy?(_value), do: false
end
