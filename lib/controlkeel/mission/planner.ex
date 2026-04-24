defmodule ControlKeel.Mission.Planner do
  @moduledoc false

  alias ControlKeel.Intent.{Domains, ExecutionBrief}
  alias ControlKeel.Mission.Decomposition
  alias ControlKeel.SecurityWorkflow

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
    "hr" => %{
      label: "HR / Recruiting",
      compliance: ["EEOC", "GDPR / CCPA", "SOC 2"],
      stack: "Phoenix + Postgres + strict role-based access and candidate PII isolation"
    },
    "marketing" => %{
      label: "Marketing",
      compliance: ["GDPR", "CAN-SPAM", "CCPA"],
      stack: "Phoenix + LiveView + consent-first architecture with double opt-in"
    },
    "sales" => %{
      label: "Sales / CRM",
      compliance: ["GDPR / CCPA", "SOC 2", "Data portability"],
      stack: "Phoenix + Postgres + CRM isolation with contact deletion support"
    },
    "realestate" => %{
      label: "Real Estate",
      compliance: ["Fair Housing Act", "RESPA basics", "GDPR / CCPA"],
      stack: "Phoenix + Postgres + encrypted document storage and transaction audit trail"
    },
    "government" => %{
      label: "Government / Public Sector",
      compliance: ["Public records retention", "Section 508", "Sensitive citizen data handling"],
      stack: "Phoenix + Postgres + audited approval workflows with retention-aware storage"
    },
    "insurance" => %{
      label: "Insurance / Claims",
      compliance: ["GLBA basics", "Claims auditability", "Privacy review"],
      stack: "Phoenix + Postgres + role-based claims workflows with dispute-friendly audit logs"
    },
    "retail" => %{
      label: "E-commerce / Retail",
      compliance: ["PCI-DSS", "GDPR / CCPA", "Fraud review controls"],
      stack: "Phoenix + payment isolation + inventory-aware storefront and returns workflows"
    },
    "logistics" => %{
      label: "Logistics / Supply Chain",
      compliance: ["Chain of custody", "Dispatch safety review", "Vendor access control"],
      stack:
        "Phoenix + evented tracking + append-only shipment history and warehouse coordination"
    },
    "manufacturing" => %{
      label: "Manufacturing / Quality",
      compliance: ["Quality traceability", "Change control", "Plant safety review"],
      stack: "Phoenix + Postgres + signed work-order and QA workflows with traceability"
    },
    "nonprofit" => %{
      label: "Nonprofit / Grants",
      compliance: ["Donor privacy", "Grant audit trails", "Beneficiary safeguards"],
      stack: "Phoenix + Postgres + grant-aware reporting and privacy-scoped service workflows"
    },
    "iot" => %{
      label: "IoT / Hardware",
      compliance: ["NIST", "Safety standards", "OWASP Top 10"],
      stack: "Phoenix API + event ingestion + device audit trails"
    },
    "security" => %{
      label: "Defensive Security",
      compliance: [
        "Coordinated disclosure",
        "Authorized target scope",
        "Patch validation evidence",
        "OWASP Top 10"
      ],
      stack:
        "Repo-local triage + typed evidence artifacts + isolated runtime exports for authorized reproduction"
    },
    "general" => %{
      label: "Other / General",
      compliance: ["OWASP Top 10", "GDPR"],
      stack: "Phoenix + LiveView + managed Postgres when scale arrives"
    }
  }

  @agent_labels %{
    # Existing
    "claude" => "Claude Code",
    "cursor" => "Cursor",
    "codex" => "Codex CLI",
    "copilot" => "GitHub Copilot",
    "windsurf" => "Windsurf",
    "replit" => "Replit",
    "bolt" => "Bolt / Lovable",
    "generic" => "Generic Agent",
    # Local IDEs
    "claude-code" => "Claude Code",
    "kiro" => "Kiro (Amazon)",
    "augment" => "Augment Code",
    "amp" => "Amp (Sourcegraph)",
    # Local CLIs
    "aider" => "Aider",
    "opencode" => "OpenCode",
    "codex-cli" => "Codex CLI",
    "gemini-cli" => "Gemini CLI",
    "antigravity" => "Antigravity",
    "continue" => "Continue",
    "ollama" => "Ollama (local)",
    # Cloud platforms
    "lovable" => "Lovable",
    "v0" => "v0 (Vercel)",
    "factory" => "Factory",
    "devin" => "Devin (Cognition)",
    "ai-studio" => "Google AI Studio",
    "generic-cli" => "Generic CLI",
    # Review & spec tools
    "coderabbit" => "CodeRabbit",
    "qodo" => "Qodo",
    "specpilot" => "SpecPilot",
    "chatprd" => "ChatPRD",
    "specced" => "Specced",
    # LLM providers
    "openai" => "OpenAI",
    "anthropic" => "Anthropic",
    "gemini" => "Google Gemini",
    "deepseek" => "DeepSeek",
    "mistral" => "Mistral AI",
    "openrouter" => "OpenRouter",
    "glm" => "Zhipu GLM",
    "kimi" => "Kimi (Moonshot)",
    "qwen" => "Qwen (Alibaba)",
    # Frameworks
    "crewai" => "CrewAI",
    "langchain" => "LangChain",
    "deepagents" => "DeepAgents",
    "nemo-guardrails" => "NeMo Guardrails",
    "langgraph" => "LangGraph",
    "autogen" => "Microsoft AutoGen",
    "semantic-kernel" => "Semantic Kernel",
    "dspy" => "DSPy",
    "haystack" => "Haystack (deepset)",
    "dify" => "Dify",
    "flowise" => "Flowise",
    "n8n" => "n8n",
    "prefect" => "Prefect",
    "mastra" => "Mastra",
    "dmux" => "dmux",
    # Cloud LLM providers (enterprise auth)
    "bedrock" => "AWS Bedrock",
    "vertex-ai" => "Google Vertex AI",
    "azure-openai" => "Azure OpenAI",
    "cohere" => "Cohere",
    "groq" => "Groq Cloud",
    "together" => "Together AI",
    "huggingface" => "Hugging Face Inference",
    "replicate" => "Replicate",
    # Managed agent platforms
    "bedrock-agents" => "AWS Bedrock Agents",
    "azure-ai-agent" => "Azure AI Agent Service",
    "vertex-ai-agent" => "Vertex AI Agent Builder",
    # Workflow automation
    "zapier" => "Zapier",
    "make" => "Make (Integromat)",
    # Observability & prompt ops
    "agentops" => "AgentOps",
    "vellum" => "Vellum",
    "promptflow" => "Azure Prompt Flow"
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
        },
        metadata: default_session_metadata()
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

    security_workflow? = brief.domain_pack == SecurityWorkflow.domain_pack()
    session_metadata = session_metadata_for_brief(brief)

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
        execution_brief: execution_brief,
        metadata: session_metadata
      },
      tasks:
        if(security_workflow?,
          do: build_security_tasks(brief),
          else:
            build_tasks(
              features,
              blank_fallback(brief.recommended_stack, "Phoenix + LiveView"),
              brief.risk_tier
            )
        ),
      findings:
        if(security_workflow?,
          do: build_security_findings(brief, budget_cents),
          else:
            build_findings(
              industry,
              Enum.join([brief.objective, brief.next_step], " "),
              brief.data_summary,
              features ++ normalize_list(brief.open_questions),
              budget_cents
            )
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

  defp industry_from_domain_pack(domain_pack), do: Domains.industry_for_pack(domain_pack)

  defp parse_budget_cents(text) do
    case Regex.run(~r/(\d+)/, text) do
      [_, amount] -> String.to_integer(amount) * 100
      _ -> 5_000
    end
  end

  defp risk_tier(industry, idea, data, features) do
    content = Enum.join([idea, data | features], " ") |> String.downcase()

    cond do
      industry == "security" ->
        "critical"

      industry in ["health", "finance", "legal", "government", "insurance"] ->
        "critical"

      industry in ["hr", "realestate", "manufacturing"] ->
        "high"

      industry == "logistics" and
          String.contains?(content, ["shipment", "dispatch", "carrier", "warehouse", "delivery"]) ->
        "high"

      industry == "nonprofit" and
          String.contains?(content, ["donor", "grant", "beneficiary", "volunteer"]) ->
        "high"

      industry == "retail" and
          String.contains?(content, ["checkout", "refund", "chargeback", "cart", "order"]) ->
        "high"

      industry == "marketing" and
          String.contains?(content, ["email list", "subscriber", "consent", "tracking", "pixel"]) ->
        "high"

      industry == "sales" and
          String.contains?(content, ["crm", "contact", "lead", "revenue", "quota"]) ->
        "high"

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
          metadata: %{
            "track" => "feature",
            "stack" => stack,
            "decomposition" => Decomposition.default_metadata_for_task("feature", nil)
          },
          confidence_score: task_confidence("feature", risk_tier),
          rollback_boundary: task_rollback("feature", feature)
        }
      end)

    [
      %{
        title: "Lock the architecture, data model, and deploy plan",
        status: "done",
        estimated_cost_cents: 15,
        validation_gate: "Decision brief approved",
        position: 1,
        metadata: %{
          "track" => "architecture",
          "stack" => stack,
          "decomposition" => Decomposition.default_metadata_for_task("architecture", nil)
        },
        confidence_score: task_confidence("arch", risk_tier),
        rollback_boundary:
          task_rollback("arch", "Lock the architecture, data model, and deploy plan")
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
          metadata: %{
            "track" => "release",
            "stack" => stack,
            "decomposition" => Decomposition.default_metadata_for_task("release", nil)
          },
          confidence_score: task_confidence("verify", risk_tier),
          rollback_boundary:
            task_rollback("verify", "Run verification, proof bundle, and release checklist")
        }
      ]
  end

  defp task_confidence(track, risk_tier) do
    base =
      case track do
        "arch" -> 0.9
        "feature" -> 0.75
        "verify" -> 0.85
        _ -> 0.70
      end

    case risk_tier do
      "critical" -> Float.round(base * 0.85, 2)
      "high" -> Float.round(base * 0.92, 2)
      _ -> base
    end
  end

  defp task_rollback("arch", _title),
    do: "No rollback — architecture decisions; discuss with team before reverting."

  defp task_rollback("verify", _title),
    do: "No rollback — verification only; no code changed."

  defp task_rollback(_track, title),
    do: "git revert HEAD~1  # reverts: #{title}"

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

  defp build_security_tasks(%ExecutionBrief{} = brief) do
    occupation = security_occupation_id(brief)
    isolation_required? = occupation == "security_researcher"

    [
      security_task(1, "discovery", "Discover and bound the vulnerability surface",
        status: "in_progress",
        track: "discovery",
        artifact_type: "source",
        validation_gate: "Authorized scope and discovery notes captured"
      ),
      security_task(2, "triage", "Triage severity, scope, and maintainer ownership",
        track: "triage",
        artifact_type: "source",
        validation_gate: "Severity and affected component reviewed"
      ),
      security_task(3, "reproduction", "Reproduce safely in an isolated runtime",
        track: "reproduction",
        artifact_type:
          if(occupation == "security_operations", do: "binary_report", else: "repro_steps"),
        validation_gate: "Verified research mode and isolated runtime required",
        requires_isolated_runtime: isolation_required? or occupation == "security_researcher"
      ),
      security_task(4, "patch", "Plan and draft the defensive patch",
        track: "feature",
        artifact_type: "diff",
        validation_gate: "Patch plan must preserve rollback and scope constraints"
      ),
      security_task(5, "validation", "Validate patch, regression coverage, and proof bundle",
        track: "verify",
        artifact_type: "diff",
        validation_gate: "Patch validation evidence and proof bundle required"
      ),
      security_task(6, "disclosure", "Prepare disclosure packet and release readiness",
        track: "release",
        artifact_type: "disclosure_text",
        validation_gate: "Disclosure state, release gate, and redaction policy reviewed"
      )
    ]
  end

  defp security_task(position, phase, title, opts) do
    status = Keyword.get(opts, :status, "queued")
    track = Keyword.get(opts, :track, phase)
    artifact_type = Keyword.fetch!(opts, :artifact_type)
    requires_isolated_runtime = Keyword.get(opts, :requires_isolated_runtime, false)

    %{
      title: title,
      status: status,
      estimated_cost_cents: 30,
      validation_gate: Keyword.fetch!(opts, :validation_gate),
      position: position,
      metadata: %{
        "track" => track,
        "security_workflow_phase" => phase,
        "artifact_type" => artifact_type,
        "requires_isolated_runtime" => requires_isolated_runtime,
        "mission_template" => "security_defender_v1",
        "decomposition" => Decomposition.default_metadata_for_task(track, phase)
      },
      confidence_score: task_confidence("feature", "critical"),
      rollback_boundary: security_task_rollback(phase)
    }
  end

  defp security_task_rollback("discovery"),
    do: "No rollback - discovery only; preserve evidence and notes."

  defp security_task_rollback("triage"),
    do: "No rollback - triage only; update severity or ownership assessment in place."

  defp security_task_rollback("reproduction"),
    do: "Destroy isolated runtime artifacts and retain only redacted evidence references."

  defp security_task_rollback("patch"),
    do: "git revert HEAD~1  # revert the drafted remediation diff if validation fails"

  defp security_task_rollback("validation"),
    do: "No rollback - validation only; keep the proof and regression evidence."

  defp security_task_rollback("disclosure"),
    do: "Retract the draft packet, preserve hashes only, and wait for maintainer sign-off."

  defp build_security_findings(%ExecutionBrief{} = brief, budget_cents) do
    occupation = security_occupation_id(brief)

    budget_findings =
      build_findings(
        "security",
        brief.objective,
        brief.data_summary,
        brief.key_features,
        budget_cents
      )

    base_metadata = %{
      finding_family: "vulnerability_case",
      affected_component: "authorization_scope",
      evidence_type: "source",
      exploitability_status: "suspected",
      patch_status: "none",
      disclosure_status: "draft",
      cwe_ids: [],
      maintainer_scope: maintainer_scope_for(occupation)
    }

    budget_findings ++
      [
        %{
          title: "Authorize the target scope before security work proceeds",
          severity: "critical",
          category: "security",
          rule_id: "security.workflow.scope_authorization",
          plain_message:
            "Security workflows must declare owned or authorized scope before discovery, reproduction, or disclosure artifacts move forward.",
          status: "open",
          auto_resolved: false,
          metadata: Map.merge(base_metadata, %{affected_component: "target_scope"})
        },
        %{
          title: "Patch validation evidence is required before release",
          severity: "high",
          category: "security",
          rule_id: "security.workflow.patch_validation",
          plain_message:
            "A vulnerability case is not release-ready until the remediation diff has proof-backed validation evidence.",
          status: "open",
          auto_resolved: false,
          metadata:
            Map.merge(base_metadata, %{
              affected_component: "patch_validation",
              evidence_type: "diff"
            })
        },
        %{
          title: "Disclosure defaults to redaction and evidence references",
          severity: "high",
          category: "security",
          rule_id: "security.workflow.disclosure_redaction",
          plain_message:
            "ControlKeel should keep disclosure packets high-level by default, referencing evidence artifacts without embedding dangerous exploit details.",
          status: "open",
          auto_resolved: false,
          metadata:
            Map.merge(base_metadata, %{
              affected_component: "disclosure_packet",
              evidence_type: "diff",
              patch_status: "drafted"
            })
        }
      ]
  end

  defp session_metadata_for_brief(%ExecutionBrief{} = brief) do
    if brief.domain_pack == SecurityWorkflow.domain_pack() do
      occupation = security_occupation_id(brief)

      default_session_metadata()
      |> Map.merge(%{
        "mission_template" => "security_defender_v1",
        "cyber_access_mode" => SecurityWorkflow.default_cyber_access_mode(occupation),
        "security_workflow_phases" => SecurityWorkflow.phases(),
        "proof_redaction_policy" => "security_default"
      })
    else
      default_session_metadata()
    end
  end

  defp default_session_metadata do
    %{
      "decomposition_strategy" => "bounded_recursive_delivery_v1",
      "decomposition_primitives" => [
        "task_graph",
        "dependency_edges",
        "review_gates",
        "resume_packets",
        "proof_bundles"
      ]
    }
  end

  defp maintainer_scope_for("open_source_maintainer"), do: "open_source"
  defp maintainer_scope_for("security_operations"), do: "third_party_vendor"
  defp maintainer_scope_for(_occupation), do: "first_party"

  defp security_occupation_id(%ExecutionBrief{} = brief) do
    brief.compiler["occupation"] || brief.occupation
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
