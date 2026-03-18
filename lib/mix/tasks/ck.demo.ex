defmodule Mix.Tasks.Ck.Demo do
  use Mix.Task

  @shortdoc "Seeds a demo session showing ControlKeel detecting a hardcoded secret"

  @moduledoc """
  Creates a demo mission that walks through the core ControlKeel detection loop:

    1. Creates a governed session for a healthcare project
    2. Runs ck_validate with content containing a hardcoded API key
    3. Reports the findings detected and the Mission Control URL

  Usage:

      mix ck.demo [--host http://localhost:4000]

  """

  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Planner

  @demo_content """
  # Patient intake webhook handler
  import requests

  ANTHROPIC_API_KEY = "sk-ant-api03-DEMO_KEY_FOR_CONTROLKEEL_DETECTION_TEST"
  OPENAI_KEY = "AKIAIOSFODNN7EXAMPLE"

  def submit_intake(patient_data):
      query = f"SELECT * FROM patients WHERE name = '{patient_data['name']}'"
      headers = {"Authorization": f"Bearer {ANTHROPIC_API_KEY}"}
      return requests.post("https://api.anthropic.com/v1/messages", headers=headers, json=patient_data)
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [host: :string])
    host = Keyword.get(opts, :host, "http://localhost:4000")

    shell = Mix.shell()
    shell.info("")
    shell.info("ControlKeel Demo — Detecting hardcoded secrets and SQL injection")
    shell.info(String.duplicate("─", 60))

    with {:ok, session} <- create_demo_session(),
         {:ok, findings} <- run_validation(session) do
      report(shell, session, findings, host)
    else
      {:error, reason} ->
        Mix.raise("Demo failed: #{inspect(reason)}")
    end
  end

  defp create_demo_session do
    shell = Mix.shell()
    shell.info("\n→ Creating demo session (healthcare domain, Claude Code agent)…")

    plan =
      Planner.build(%{
        "industry" => "health",
        "agent" => "claude",
        "idea" => "Patient intake and webhook handler for a small clinic",
        "users" => "Clinic front desk staff",
        "data" => "Patient names, intake forms, appointment notes",
        "features" => "Intake form, webhook handler, staff review queue",
        "budget" => "20",
        "project_name" => "ControlKeel Demo — Clinic Intake"
      })

    case persist_demo_plan(plan) do
      {:ok, session} ->
        shell.info("  ✓ Session created: #{session.title} (id: #{session.id})")
        shell.info("  ✓ Risk tier: #{session.risk_tier}")
        shell.info("  ✓ Budget: $#{div(session.budget_cents, 100)}/day")
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_demo_plan(plan) do
    alias ControlKeel.Mission.{Workspace, Session, Task, Finding}
    alias ControlKeel.Repo
    alias Ecto.Multi

    Multi.new()
    |> Multi.insert(:workspace, Workspace.changeset(%Workspace{}, plan.workspace))
    |> Multi.insert(:session, fn %{workspace: workspace} ->
      Session.changeset(%Session{}, Map.put(plan.session, :workspace_id, workspace.id))
    end)
    |> Multi.run(:tasks, fn repo, %{session: session} ->
      Enum.reduce_while(plan.tasks, {:ok, []}, fn attrs, {:ok, acc} ->
        case repo.insert(Task.changeset(%Task{}, Map.put(attrs, :session_id, session.id))) do
          {:ok, task} -> {:cont, {:ok, [task | acc]}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)
    end)
    |> Multi.run(:findings, fn repo, %{session: session} ->
      Enum.reduce_while(plan.findings, {:ok, []}, fn attrs, {:ok, acc} ->
        case repo.insert(Finding.changeset(%Finding{}, Map.put(attrs, :session_id, session.id))) do
          {:ok, f} -> {:cont, {:ok, [f | acc]}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, Mission.get_session_context(session.id)}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  defp run_validation(session) do
    shell = Mix.shell()

    shell.info(
      "\n→ Running ck_validate with content containing hardcoded secrets + SQL injection…"
    )

    shell.info("  (Simulating what Claude Code would send via MCP)")

    result =
      CkValidate.call(%{
        "content" => @demo_content,
        "path" => "app/intake_handler.py",
        "kind" => "code",
        "session_id" => session.id
      })

    case result do
      {:ok, %{"decision" => decision, "findings" => findings}} ->
        shell.info("  ✓ Scanner decision: #{String.upcase(decision)}")
        shell.info("  ✓ Findings detected: #{length(findings)}")
        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp report(shell, session, findings, host) do
    shell.info("\n#{String.duplicate("─", 60)}")
    shell.info("FINDINGS DETECTED")
    shell.info(String.duplicate("─", 60))

    Enum.each(findings, fn finding ->
      shell.info("")
      shell.info("  [#{String.upcase(finding["severity"] || "?")}] #{finding["rule_id"]}")
      shell.info("  #{finding["plain_message"] || finding["summary"]}")
    end)

    shell.info("")
    shell.info(String.duplicate("─", 60))
    shell.info("NEXT STEPS")
    shell.info(String.duplicate("─", 60))
    shell.info("")
    shell.info("  Open Mission Control to review and approve findings:")
    shell.info("")
    shell.info("    #{host}/missions/#{session.id}")
    shell.info("")
    shell.info("  Or review all findings:")
    shell.info("")
    shell.info("    #{host}/findings?session_id=#{session.id}")
    shell.info("")
    shell.info("  View active policy packs:")
    shell.info("")
    shell.info("    #{host}/policies")
    shell.info("")
  end
end
