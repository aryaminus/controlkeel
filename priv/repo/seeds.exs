# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seeds a demo healthcare workspace + session so Mission Control is usable
# without having to run `mix ck.demo` first.

alias ControlKeel.Mission
alias ControlKeel.Repo

# ── Workspace ─────────────────────────────────────────────────────────────────

{:ok, workspace} =
  Mission.create_workspace(%{
    name: "ControlKeel Demo — Clinic Intake",
    industry: "health",
    agent: "claude-code",
    slug: "controlkeel-demo-clinic-#{System.unique_integer([:positive])}",
    budget_cents: 5_000,
    compliance_profile: "HIPAA, OWASP Top 10",
    status: "active"
  })

IO.puts("  ✓ Workspace: #{workspace.name} (id: #{workspace.id})")

# ── Session ───────────────────────────────────────────────────────────────────

{:ok, session} =
  Mission.create_session(%{
    title: "Patient Intake Workflow v1",
    objective: "Build a patient intake form, webhook handler, and staff review queue for a small clinic",
    risk_tier: "critical",
    status: "in_progress",
    budget_cents: 5_000,
    daily_budget_cents: 2_000,
    spent_cents: 320,
    execution_brief: %{
      "agent" => "claude-code",
      "domain_pack" => "healthcare",
      "recommended_stack" => "Phoenix + LiveView + Cloak encryption",
      "compliance" => ["HIPAA", "OWASP Top 10"],
      "risk_tier" => "critical"
    },
    workspace_id: workspace.id
  })

IO.puts("  ✓ Session: #{session.title} (id: #{session.id})")

# ── Tasks ─────────────────────────────────────────────────────────────────────

tasks = [
  %{
    title: "Design patient intake schema with encrypted PHI fields",
    validation_gate: "Schema review + Cloak field type audit",
    estimated_cost_cents: 40,
    position: 1,
    status: "done",
    session_id: session.id
  },
  %{
    title: "Build intake form LiveView component",
    validation_gate: "Security scan + HIPAA field review",
    estimated_cost_cents: 60,
    position: 2,
    status: "in_progress",
    session_id: session.id
  },
  %{
    title: "Implement webhook handler for EHR system",
    validation_gate: "No hardcoded keys + TLS validation",
    estimated_cost_cents: 50,
    position: 3,
    status: "queued",
    session_id: session.id
  },
  %{
    title: "Add staff review queue with approval flow",
    validation_gate: "Auth check + rate limiting",
    estimated_cost_cents: 55,
    position: 4,
    status: "queued",
    session_id: session.id
  }
]

Enum.each(tasks, fn attrs ->
  {:ok, task} = Mission.create_task(attrs)
  IO.puts("  ✓ Task [#{task.position}]: #{task.title}")
end)

# ── Findings ──────────────────────────────────────────────────────────────────

findings = [
  %{
    title: "Hardcoded Anthropic API key in webhook handler",
    rule_id: "secret.aws_access_key",
    category: "secret",
    severity: "critical",
    status: "open",
    plain_message:
      "A hardcoded API key was found in app/intake_handler.py. Rotate immediately and migrate to an environment variable.",
    auto_resolved: false,
    metadata: %{"path" => "app/intake_handler.py", "line" => 4},
    session_id: session.id
  },
  %{
    title: "SQL injection in patient lookup query",
    rule_id: "security.sql_injection",
    category: "security",
    severity: "critical",
    status: "blocked",
    plain_message:
      "User input is concatenated directly into the SQL query in app/intake_handler.py. Use parameterized queries.",
    auto_resolved: false,
    metadata: %{"path" => "app/intake_handler.py", "line" => 8},
    session_id: session.id
  },
  %{
    title: "Unencrypted PHI field in patient schema",
    rule_id: "healthcare.phi_pattern",
    category: "healthcare",
    severity: "high",
    status: "open",
    plain_message:
      "The `ssn` and `date_of_birth` fields in the Patient schema are stored as plain strings. Encrypt with Cloak.",
    auto_resolved: false,
    metadata: %{"path" => "lib/clinic/patient.ex", "line" => 5},
    session_id: session.id
  },
  %{
    title: "PHI logging — patient name in audit trail",
    rule_id: "gdpr.personal_data_logging",
    category: "privacy",
    severity: "medium",
    status: "approved",
    plain_message:
      "Patient full_name is logged in the intake submission handler. Replace with patient_id to avoid PHI in logs.",
    auto_resolved: false,
    metadata: %{"path" => "app/intake_handler.py", "line" => 12},
    session_id: session.id
  }
]

Enum.each(findings, fn attrs ->
  {:ok, finding} = Mission.create_finding(attrs)
  IO.puts("  ✓ Finding [#{finding.severity}] #{finding.title}")
end)

IO.puts("")
IO.puts("Seeds complete. Visit:")
IO.puts("  http://localhost:4000/missions/#{session.id}")
IO.puts("  http://localhost:4000/findings?session_id=#{session.id}")
