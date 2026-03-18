defmodule ControlKeel.Mission.Planner do
  @moduledoc false

  alias ControlKeel.Intent.ExecutionBrief

  @industry_profiles %{
    "web" => %{
      label: "Web App / SaaS",
      compliance: ["GDPR", "SOC 2", "OWASP Top 10"],
      stack: "Phoenix + LiveView + SQLite for fast local-first delivery"
    },
    "health" => %{
      label: "Healthcare",
      compliance: ["HIPAA", "HITECH", "OWASP Top 10"],
      stack: "Phoenix + Postgres + encrypted storage with strict audit logging"
    },
    "finance" => %{
      label: "Finance / Fintech",
      compliance: ["PCI-DSS", "SOX", "OWASP Top 10"],
      stack: "Phoenix + Postgres + role-based access and immutable audit trails"
    },
    "ecommerce" => %{
      label: "E-Commerce",
      compliance: ["PCI-DSS", "GDPR", "WCAG 2.1 AA"],
      stack: "Phoenix + Stripe-style payments isolation + CDN-backed storefront"
    },
    "education" => %{
      label: "Education",
      compliance: ["FERPA", "COPPA", "WCAG 2.1 AA"],
      stack: "Phoenix + LiveView + strict content and access controls"
    },
    "legal" => %{
      label: "Legal",
      compliance: ["Privilege handling", "Retention policy", "eDiscovery readiness"],
      stack: "Phoenix + encrypted document storage + role-aware review workflows"
    },
    "iot" => %{
      label: "IoT / Hardware",
      compliance: ["NIST", "Safety standards", "OWASP Top 10"],
      stack: "Phoenix API + event ingestion + device audit trails"
    },
    "general" => %{
      label: "Other / General",
      compliance: ["OWASP Top 10", "GDPR"],
      stack: "Phoenix + LiveView + managed Postgres when scale arrives"
    }
  }

  @agent_labels %{
    "claude" => "Claude Code",
    "cursor" => "Cursor",
    "codex" => "Codex CLI",
    "copilot" => "GitHub Copilot",
    "windsurf" => "Windsurf",
    "replit" => "Replit",
    "bolt" => "Bolt / Lovable",
    "generic" => "Generic Agent"
  }

  def build(attrs) do
    industry = value(attrs, "industry", "general")
    agent = value(attrs, "agent", "claude")
    idea = value(attrs, "idea")
    users = value(attrs, "users")
    data = value(attrs, "data")
    features = split_features(value(attrs, "features"))
    budget_text = value(attrs, "budget")
    budget_cents = parse_budget_cents(budget_text)
    project_root = value(attrs, "project_root")
    profile = Map.fetch!(@industry_profiles, industry)
    risk_tier = risk_tier(industry, idea, data, features)
    compliance = compliance_for(profile, data)
    stack = recommended_stack(profile, risk_tier)
    objective = objective_from(idea, users)
    title = title_from(attrs, idea)

    %{
      workspace: %{
        name: title,
        slug: workspace_slug(title, project_root),
        industry: industry,
        agent: agent,
        budget_cents: budget_cents,
        compliance_profile: Enum.join(compliance, ", "),
        status: "active"
      },
      session: %{
        title: title,
        objective: objective,
        risk_tier: risk_tier,
        status: "in_progress",
        budget_cents: budget_cents,
        daily_budget_cents: daily_budget_cents(budget_cents),
        spent_cents: estimated_spend(budget_cents),
        execution_brief: %{
          objective: objective,
          users: users,
          data_summary: data,
          key_features: features,
          budget_note: blank_fallback(budget_text, "Budget not specified"),
          recommended_stack: stack,
          compliance: compliance,
          risk_tier: risk_tier,
          agent: Map.get(@agent_labels, agent, "Generic Agent"),
          launch_window: launch_window(risk_tier),
          next_step: next_step(risk_tier)
        }
      },
      tasks: build_tasks(features, stack, risk_tier),
      findings: build_findings(industry, idea, data, features, budget_cents)
    }
  end

  def build_from_brief(%ExecutionBrief{} = brief, attrs \\ %{}) do
    agent = value(attrs, "agent", "claude")
    budget_text = value(attrs, "budget", brief.budget_note || "")
    budget_cents = parse_budget_cents(budget_text)
    project_root = value(attrs, "project_root")
    industry = industry_from_domain_pack(brief.domain_pack)

    title =
      title_from(
        %{"project_name" => brief.project_name || "", "idea" => brief.idea || ""},
        brief.idea || ""
      )

    compliance = normalize_list(brief.compliance)
    features = features_from_brief(brief)

    execution_brief =
      brief
      |> ExecutionBrief.to_map()
      |> Map.put("agent", Map.get(@agent_labels, agent, "Generic Agent"))

    %{
      workspace: %{
        name: title,
        slug: workspace_slug(title, project_root),
        industry: industry,
        agent: agent,
        budget_cents: budget_cents,
        compliance_profile: Enum.join(compliance, ", "),
        status: "active"
      },
      session: %{
        title: title,
        objective: brief.objective,
        risk_tier: brief.risk_tier,
        status: "in_progress",
        budget_cents: budget_cents,
        daily_budget_cents: daily_budget_cents(budget_cents),
        spent_cents: estimated_spend(budget_cents),
        execution_brief: execution_brief
      },
      tasks:
        build_tasks(
          features,
          blank_fallback(brief.recommended_stack, "Phoenix + LiveView"),
          brief.risk_tier
        ),
      findings:
        build_findings(
          industry,
          Enum.join([brief.objective, brief.next_step], " "),
          brief.data_summary,
          features ++ normalize_list(brief.open_questions),
          budget_cents
        )
    }
  end

  def industries, do: @industry_profiles
  def agent_labels, do: @agent_labels

  defp value(attrs, key, default \\ "") do
    attrs
    |> Map.get(key, default)
    |> to_string()
    |> String.trim()
  end

  defp blank_fallback("", fallback), do: fallback
  defp blank_fallback(value, _fallback), do: value

  defp split_features(features) do
    features
    |> String.split(~r/[\n,]/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(5)
    |> case do
      [] -> ["Define the first user-facing workflow", "Add validation and deployment checks"]
      values -> values
    end
  end

  defp features_from_brief(%ExecutionBrief{} = brief) do
    brief.key_features
    |> normalize_list()
    |> case do
      [] ->
        brief.acceptance_criteria
        |> normalize_list()
        |> Enum.map(&criterion_to_feature/1)
        |> Enum.take(max(brief.estimated_tasks - 2, 1))

      values ->
        values
    end
  end

  defp normalize_list(nil), do: []

  defp normalize_list(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp criterion_to_feature(criterion) do
    criterion
    |> String.trim()
    |> String.trim_trailing(".")
    |> case do
      "" -> "Define the first user-facing workflow"
      value -> value
    end
  end

  defp industry_from_domain_pack("healthcare"), do: "health"
  defp industry_from_domain_pack("education"), do: "education"
  defp industry_from_domain_pack(_domain_pack), do: "web"

  defp parse_budget_cents(text) do
    case Regex.run(~r/(\d+)/, text) do
      [_, amount] -> String.to_integer(amount) * 100
      _ -> 5_000
    end
  end

  defp risk_tier(industry, idea, data, features) do
    content = Enum.join([idea, data | features], " ") |> String.downcase()

    cond do
      industry in ["health", "finance", "legal"] ->
        "critical"

      String.contains?(content, [
        "patient",
        "medical",
        "card",
        "payment",
        "salary",
        "social security"
      ]) ->
        "critical"

      String.contains?(content, ["personal", "account", "auth", "login", "upload", "admin"]) ->
        "high"

      true ->
        "moderate"
    end
  end

  defp compliance_for(profile, data) do
    extra =
      data
      |> String.downcase()
      |> then(fn text ->
        []
        |> maybe_add(String.contains?(text, ["email", "address", "phone"]), "PII handling")
        |> maybe_add(
          String.contains?(text, ["medical", "patient", "health"]),
          "Sensitive health data review"
        )
        |> maybe_add(String.contains?(text, ["payment", "card", "billing"]), "Payment isolation")
      end)

    profile.compliance ++ extra
  end

  defp recommended_stack(profile, "critical"),
    do: profile.stack <> "; require human approval before deploy"

  defp recommended_stack(profile, _risk_tier), do: profile.stack

  defp objective_from("", _users),
    do: "Stand up the first production-safe version of the requested workflow."

  defp objective_from(idea, users) do
    users_line = if users == "", do: "for the first users", else: "for #{users}"
    "Build #{String.downcase(idea)} #{users_line} with secure defaults and manageable scope."
  end

  defp title_from(attrs, idea) do
    candidate = value(attrs, "project_name")

    cond do
      candidate != "" ->
        candidate

      idea == "" ->
        "ControlKeel Mission"

      true ->
        idea
        |> String.split(~r/[.!?]/, trim: true)
        |> List.first()
        |> String.trim()
        |> String.slice(0, 48)
    end
  end

  defp build_tasks(features, stack, risk_tier) do
    feature_tasks =
      features
      |> Enum.with_index(2)
      |> Enum.map(fn {feature, index} ->
        %{
          title: feature,
          status: if(index == 2, do: "in_progress", else: "queued"),
          estimated_cost_cents: 35,
          validation_gate: validation_gate(risk_tier),
          position: index,
          metadata: %{track: "feature", stack: stack}
        }
      end)

    [
      %{
        title: "Lock the architecture, data model, and deploy plan",
        status: "done",
        estimated_cost_cents: 15,
        validation_gate: "Decision brief approved",
        position: 1,
        metadata: %{track: "architecture", stack: stack}
      }
      | feature_tasks
    ] ++
      [
        %{
          title: "Run verification, proof bundle, and release checklist",
          status: "queued",
          estimated_cost_cents: 20,
          validation_gate: "Tests, scans, and rollback notes complete",
          position: length(feature_tasks) + 2,
          metadata: %{track: "release", stack: stack}
        }
      ]
  end

  defp build_findings(industry, idea, data, features, budget_cents) do
    content = Enum.join([idea, data | features], " ") |> String.downcase()

    base = [
      %{
        title: "Define a hard budget ceiling before long agent runs",
        severity: if(budget_cents <= 2_000, do: "medium", else: "low"),
        category: "cost",
        rule_id: "cost.budget_guard",
        plain_message:
          "ControlKeel will cap spend per session so the agent cannot silently burn through your budget while iterating.",
        status: "open",
        auto_resolved: false,
        metadata: %{budget_cents: budget_cents}
      }
    ]

    base
    |> maybe_append(String.contains?(content, ["login", "auth", "account", "admin"]), %{
      title: "Authentication flow needs explicit review",
      severity: "high",
      category: "security",
      rule_id: "security.auth.review",
      plain_message:
        "This mission includes account or admin access. Require approval before exposing authentication to production.",
      status: "open",
      auto_resolved: false,
      metadata: %{industry: industry}
    })
    |> maybe_append(String.contains?(content, ["payment", "card", "billing"]), %{
      title: "Payment handling must stay out of app code",
      severity: "critical",
      category: "compliance",
      rule_id: "compliance.payment.isolation",
      plain_message:
        "Use a hosted payment provider and keep raw card data out of the product surface and agent-generated code.",
      status: "open",
      auto_resolved: false,
      metadata: %{industry: industry}
    })
    |> maybe_append(String.contains?(content, ["patient", "medical", "health"]), %{
      title: "Sensitive health data detected",
      severity: "critical",
      category: "privacy",
      rule_id: "privacy.phi.review",
      plain_message:
        "The brief suggests health-related data. Keep the first release local or tightly hosted until audit logging and access control are explicit.",
      status: "open",
      auto_resolved: false,
      metadata: %{industry: industry}
    })
    |> maybe_append(String.contains?(content, ["upload", "file", "document"]), %{
      title: "File uploads need type and malware gates",
      severity: "medium",
      category: "security",
      rule_id: "security.upload.validation",
      plain_message:
        "User uploads expand the attack surface. Add file-type validation, storage isolation, and scanning before launch.",
      status: "open",
      auto_resolved: false,
      metadata: %{industry: industry}
    })
  end

  defp validation_gate("critical"), do: "Security scan, human approval, and rollback plan"
  defp validation_gate("high"), do: "Security scan and proof bundle"
  defp validation_gate(_), do: "Passing checks and proof bundle"

  defp launch_window("critical"), do: "Launch behind approvals with staged access"
  defp launch_window("high"), do: "Launch after one controlled internal pass"
  defp launch_window(_), do: "Launch after a lightweight verification pass"

  defp next_step("critical"),
    do: "Start with architecture and policy constraints before code generation"

  defp next_step("high"), do: "Generate a small first slice and keep the PR surface tight"
  defp next_step(_), do: "Ship the narrowest useful workflow and validate it quickly"

  defp estimated_spend(budget_cents), do: min(div(max(budget_cents, 500), 5), 1_500)

  defp daily_budget_cents(0), do: 0
  defp daily_budget_cents(budget_cents), do: budget_cents

  defp maybe_add(list, true, value), do: list ++ [value]
  defp maybe_add(list, false, _value), do: list

  defp maybe_append(list, true, value), do: list ++ [value]
  defp maybe_append(list, false, _value), do: list

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "controlkeel-mission"
      slug -> slug
    end
  end

  defp workspace_slug(title, ""), do: slugify(title)

  defp workspace_slug(title, project_root) do
    fingerprint =
      :crypto.hash(:sha256, project_root)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    slugify("#{title}-#{fingerprint}")
  end
end
