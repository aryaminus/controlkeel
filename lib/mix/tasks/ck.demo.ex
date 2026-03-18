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

  # Benchmark scenarios based on documented real-world vibe coding failures.
  # Each represents a class of issue that AI coding agents produce without governance.

  @scenarios [
    %{
      name: "Hardcoded API key in Python webhook",
      path: "app/intake_handler.py",
      kind: "code",
      content: """
      import requests

      ANTHROPIC_API_KEY = "sk-ant-api03-DEMO_KEY_FOR_CONTROLKEEL_DETECTION_TEST"
      OPENAI_KEY = "AKIAIOSFODNN7EXAMPLE"

      def submit_intake(patient_data):
          query = f"SELECT * FROM patients WHERE name = '{patient_data['name']}'"
          headers = {"Authorization": f"Bearer {ANTHROPIC_API_KEY}"}
          return requests.post("https://api.anthropic.com/v1/messages", headers=headers, json=patient_data)
      """
    },
    %{
      name: "Client-side auth bypass (Enrichlead pattern)",
      path: "src/auth/guard.js",
      kind: "code",
      content: """
      // Role check performed only in the browser — server never validates
      function checkAdmin(user) {
        if (localStorage.getItem('role') === 'admin') {
          return true;
        }
        return false;
      }

      document.getElementById('admin-panel').innerHTML = userData;
      """
    },
    %{
      name: "Supabase storage bucket public (Moltbook pattern)",
      path: "supabase/storage.sql",
      kind: "code",
      content: """
      -- Create public bucket with no RLS
      INSERT INTO storage.buckets (id, name, public) VALUES ('user-uploads', 'user-uploads', true);

      CREATE POLICY "allow all" ON storage.objects FOR ALL USING (true);

      SELECT * FROM users WHERE email = '""" <> "' || input || '" <> """'
      """
    },
    %{
      name: "Unencrypted PHI field in Ecto schema",
      path: "lib/clinic/patient.ex",
      kind: "code",
      content: """
      schema "patients" do
        field :full_name, :string
        field :date_of_birth, :string
        field :ssn, :string
        field :email, :string
        field :phone_number, :string
        field :home_address, :string
      end
      """
    },
    %{
      name: "eval() with user input (SaaStr autonomous agent pattern)",
      path: "scripts/data_processor.js",
      kind: "code",
      content: """
      const userScript = req.body.script;
      // Agent generated this to be 'flexible'
      eval(userScript);

      // Also logging user PII
      console.log('Processing for user:', user.email, user.full_name);
      """
    },
    %{
      name: "Hardcoded DB password in Docker config",
      path: "docker-compose.yml",
      kind: "code",
      content: """
      version: '3.8'
      services:
        db:
          image: postgres:16
          environment:
            POSTGRES_PASSWORD: "SuperSecret123!"
            POSTGRES_USER: "admin"
            DATABASE_URL: "postgresql://admin:SuperSecret123!@db:5432/myapp"
      """
    },
    %{
      name: "Open redirect via user input",
      path: "app/controllers/sessions_controller.rb",
      kind: "code",
      content: """
      def create
        if @user.authenticate(params[:password])
          redirect_to params[:return_url]  # user-controlled redirect
        end
      end
      """
    },
    %{
      name: "Personal data sent to third-party without DPA",
      path: "lib/analytics/tracker.ex",
      kind: "code",
      content: """
      def track_signup(user) do
        Req.post(url: "https://api.segment.io/v1/track",
          json: %{
            userId: user.id,
            email: user.email,
            full_name: user.full_name,
            customer_id: user.id
          })
      end
      """
    },
    %{
      name: "Debug mode enabled in production config",
      path: "config/production.py",
      kind: "code",
      content: """
      DEBUG = True
      SECRET_KEY = "dev-secret-key-do-not-use"
      ALLOWED_HOSTS = ['*']
      DATABASE_URL = "postgresql://prod_user:ProdPass99@db.internal/prod"
      """
    },
    %{
      name: "pickle.loads with untrusted data (deserialization RCE)",
      path: "api/deserialize.py",
      kind: "code",
      content: """
      import pickle, base64

      def load_session(session_data):
          # Agent deserialized user-supplied base64 data directly
          return pickle.loads(base64.b64decode(session_data))
      """
    }
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [host: :string, scenario: :integer])
    host = Keyword.get(opts, :host, "http://localhost:4000")
    scenario_idx = Keyword.get(opts, :scenario)

    scenarios =
      if scenario_idx do
        [Enum.at(@scenarios, scenario_idx - 1) || hd(@scenarios)]
      else
        @scenarios
      end

    shell = Mix.shell()
    shell.info("")
    shell.info("ControlKeel Benchmark — #{length(scenarios)} vibe coding failure scenario(s)")
    shell.info(String.duplicate("─", 64))

    with {:ok, session} <- create_demo_session(),
         results <- run_benchmark(session, scenarios, shell) do
      report_benchmark(shell, session, results, host)
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

  defp run_benchmark(session, scenarios, shell) do
    shell.info("\n→ Running #{length(scenarios)} benchmark scenario(s) via ck_validate…")
    shell.info("  (Simulating what Claude Code sends via MCP on each tool call)\n")

    Enum.with_index(scenarios, 1)
    |> Enum.map(fn {scenario, idx} ->
      result =
        CkValidate.call(%{
          "content" => scenario.content,
          "path" => scenario.path,
          "kind" => scenario.kind,
          "session_id" => session.id
        })

      case result do
        {:ok, %{"decision" => decision, "findings" => findings}} ->
          caught = length(findings)
          badge = if decision == "block", do: "BLOCKED", else: "WARNED "
          shell.info("  [#{idx}/#{length(@scenarios)}] #{badge} #{scenario.name}")
          shell.info("         #{caught} finding(s) — decision: #{String.upcase(decision)}")
          %{scenario: scenario.name, decision: decision, findings: findings, caught: caught}

        {:error, reason} ->
          shell.info("  [#{idx}/#{length(@scenarios)}] ERROR   #{scenario.name}: #{inspect(reason)}")
          %{scenario: scenario.name, decision: "error", findings: [], caught: 0}
      end
    end)
  end

  defp report_benchmark(shell, session, results, host) do
    total = length(results)
    caught = Enum.count(results, &(&1.caught > 0))
    blocked = Enum.count(results, &(&1.decision == "block"))
    total_findings = Enum.sum(Enum.map(results, & &1.caught))
    catch_rate = if total > 0, do: round(caught / total * 100), else: 0

    shell.info("")
    shell.info(String.duplicate("─", 64))
    shell.info("BENCHMARK RESULTS")
    shell.info(String.duplicate("─", 64))
    shell.info("")
    shell.info("  Scenarios run:        #{total}")
    shell.info("  Scenarios with finds: #{caught}/#{total}  (#{catch_rate}% catch rate)")
    shell.info("  Hard blocks:          #{blocked}")
    shell.info("  Total findings:       #{total_findings}")
    shell.info("")

    Enum.each(results, fn r ->
      icon = cond do
        r.decision == "block" -> "✗ BLOCKED"
        r.caught > 0 -> "⚠ WARNED "
        true -> "✓ PASSED "
      end
      shell.info("  #{icon}  #{r.scenario}")
    end)

    shell.info("")
    shell.info(String.duplicate("─", 64))
    shell.info("REVIEW IN MISSION CONTROL")
    shell.info("")
    shell.info("  #{host}/missions/#{session.id}")
    shell.info("  #{host}/findings?session_id=#{session.id}")
    shell.info("  #{host}/policies")
    shell.info("")
    shell.info("  View active policy packs:")
    shell.info("")
    shell.info("    #{host}/policies")
    shell.info("")
  end
end
