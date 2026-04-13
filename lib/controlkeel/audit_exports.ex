defmodule ControlKeel.AuditExports do
  @moduledoc false

  alias ControlKeel.Runtime

  def render(session, audit_log, graph, proofs, format) when format in ["json", "csv", "pdf"] do
    case format do
      "json" ->
        payload = Jason.encode!(audit_payload(session, audit_log, graph, proofs), pretty: true)
        {:ok, payload, artifact_metadata(payload, "inline:json")}

      "csv" ->
        payload = to_csv(audit_log)
        {:ok, payload, artifact_metadata(payload, "inline:csv")}

      "pdf" ->
        html = to_html(session, audit_log, graph, proofs)

        case Runtime.pdf_renderer().render(html) do
          {:ok, binary} ->
            artifact_path = persist_binary(binary, "pdf")
            {:ok, binary, artifact_metadata(binary, artifact_path)}

          other ->
            other
        end
    end
  end

  def audit_payload(session, audit_log, graph, proofs) do
    %{
      audit_log: audit_log,
      session: %{
        id: session.id,
        title: session.title,
        objective: session.objective,
        risk_tier: session.risk_tier,
        workspace_id: session.workspace_id,
        domain_pack: get_in(session.execution_brief || %{}, ["domain_pack"])
      },
      graph: graph,
      proofs: Enum.map(proofs, &proof_summary/1)
    }
  end

  def to_csv(%{events: events, session_id: sid, session_title: title}) do
    header =
      "session_id,session_title,timestamp,type,source_or_rule,severity_or_decision,plain_message\n"

    rows =
      Enum.map(events, fn event ->
        source_or_rule = Map.get(event, :source) || Map.get(event, :rule_id, "")
        severity_or_decision = Map.get(event, :severity) || Map.get(event, :decision, "")

        [
          csv_escape(to_string(sid)),
          csv_escape(title),
          csv_escape(format_timestamp(event.timestamp)),
          csv_escape(event.type),
          csv_escape(to_string(source_or_rule)),
          csv_escape(to_string(severity_or_decision)),
          csv_escape(Map.get(event, :plain_message, ""))
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\n")
  end

  def to_html(session, audit_log, graph, proofs) do
    domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"]) || "unknown"
    checksum = checksum(Jason.encode!(audit_log))

    proof_items =
      proofs
      |> Enum.map(fn proof ->
        "<li><strong>#{escape_html(proof.task.title)}</strong> — v#{proof.version}, status #{escape_html(proof.status)}, deploy ready: #{proof.deploy_ready}</li>"
      end)
      |> Enum.join()

    task_rows =
      graph.tasks
      |> Enum.map(fn task ->
        "<tr><td>#{task.position}</td><td>#{escape_html(task.title)}</td><td>#{escape_html(task.status)}</td><td>#{task.incoming_count}</td><td>#{task.outgoing_count}</td></tr>"
      end)
      |> Enum.join()

    event_rows =
      audit_log.events
      |> Enum.map(fn event ->
        "<tr><td>#{escape_html(format_timestamp(event.timestamp))}</td><td>#{escape_html(event.type)}</td><td>#{escape_html(to_string(Map.get(event, :source) || Map.get(event, :rule_id, "")))}</td><td>#{escape_html(to_string(Map.get(event, :severity) || Map.get(event, :decision, "")))}</td><td>#{escape_html(Map.get(event, :plain_message, ""))}</td></tr>"
      end)
      |> Enum.join()

    attestation_items =
      proofs
      |> Enum.flat_map(fn proof -> get_in(proof.bundle, ["compliance_attestations"]) || [] end)
      |> Enum.uniq_by(&{&1["pack"], &1["status"], &1["blocked_count"]})
      |> Enum.map(fn attestation ->
        "<li>#{escape_html(attestation["pack"])} — #{escape_html(attestation["status"])} (#{attestation["findings_count"]} findings, #{attestation["blocked_count"]} blocked)</li>"
      end)
      |> Enum.join()

    """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <style>
          body { font-family: Helvetica, Arial, sans-serif; color: #0f172a; margin: 2rem; }
          h1, h2 { margin-bottom: 0.4rem; }
          .meta { color: #475569; margin-bottom: 1.5rem; }
          table { width: 100%; border-collapse: collapse; margin: 1rem 0 1.5rem; font-size: 12px; }
          th, td { border: 1px solid #cbd5e1; padding: 0.5rem; text-align: left; vertical-align: top; }
          th { background: #e2e8f0; }
          .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; }
          .card { background: #f8fafc; border: 1px solid #e2e8f0; padding: 1rem; border-radius: 12px; }
          ul { padding-left: 1.1rem; }
          code { font-family: Menlo, Monaco, monospace; }
        </style>
      </head>
      <body>
        <h1>ControlKeel Audit Report</h1>
        <p class="meta">Session ##{session.id} • #{escape_html(session.title)} • domain #{escape_html(domain_pack)} • checksum #{checksum}</p>

        <div class="grid">
          <section class="card">
            <h2>Session Summary</h2>
            <p><strong>Objective:</strong> #{escape_html(session.objective || "")}</p>
            <p><strong>Risk tier:</strong> #{escape_html(session.risk_tier || "unknown")}</p>
            <p><strong>Total findings:</strong> #{audit_log.summary.total_findings}</p>
            <p><strong>Total invocations:</strong> #{audit_log.summary.total_invocations}</p>
            <p><strong>Total cost:</strong> #{audit_log.summary.total_cost_cents} cents</p>
          </section>
          <section class="card">
            <h2>Task Graph Summary</h2>
            <p><strong>Total tasks:</strong> #{length(graph.tasks)}</p>
            <p><strong>Total edges:</strong> #{length(graph.edges)}</p>
            <p><strong>Ready tasks:</strong> #{length(graph.ready_task_ids)}</p>
            <p><strong>Completed tasks:</strong> #{Enum.count(graph.tasks, &(&1.status in ["done", "verified"]))}</p>
          </section>
        </div>

        <h2>Tasks</h2>
        <table>
          <thead><tr><th>Position</th><th>Task</th><th>Status</th><th>Incoming</th><th>Outgoing</th></tr></thead>
          <tbody>#{task_rows}</tbody>
        </table>

        <h2>Invocation and Finding Timeline</h2>
        <table>
          <thead><tr><th>Timestamp</th><th>Type</th><th>Source</th><th>Decision</th><th>Message</th></tr></thead>
          <tbody>#{event_rows}</tbody>
        </table>

        <h2>Proof Bundle Summary</h2>
        <ul>#{proof_items}</ul>

        <h2>Compliance Attestations</h2>
        <ul>#{attestation_items}</ul>

        <p class="meta">Generated #{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()} • checksum #{checksum}</p>
      </body>
    </html>
    """
  end

  def checksum(binary) when is_binary(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  defp proof_summary(proof) do
    %{
      id: proof.id,
      task_id: proof.task_id,
      version: proof.version,
      status: proof.status,
      deploy_ready: proof.deploy_ready,
      risk_score: proof.risk_score
    }
  end

  defp artifact_metadata(binary, artifact_path_or_ref) do
    %{
      checksum: checksum(binary),
      artifact_path_or_ref: artifact_path_or_ref,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp persist_binary(binary, extension) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-audit-exports"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "#{System.unique_integer([:positive])}.#{extension}")
    File.write!(path, binary)
    path
  end

  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp format_timestamp(other), do: to_string(other || "")

  defp csv_escape(nil), do: ""
  defp csv_escape(value), do: ~s("#{String.replace(to_string(value), "\"", "\"\"")}")

  defp escape_html(value) do
    Phoenix.HTML.html_escape(value || "")
    |> Phoenix.HTML.safe_to_string()
  end
end
