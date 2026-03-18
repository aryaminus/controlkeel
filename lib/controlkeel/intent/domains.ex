defmodule ControlKeel.Intent.Domains do
  @moduledoc false

  @occupation_profiles [
    %{
      id: "founder",
      label: "Founder / Product Builder",
      domain_pack: "software",
      industry: "web",
      description: "Apps, SaaS, internal tools, marketplaces, automations"
    },
    %{
      id: "operator",
      label: "Operations / Back Office",
      domain_pack: "software",
      industry: "web",
      description: "Internal workflows, approvals, analytics, support tooling"
    },
    %{
      id: "healthcare",
      label: "Healthcare",
      domain_pack: "healthcare",
      industry: "health",
      description: "Clinics, patient intake, billing, care-team operations"
    },
    %{
      id: "education",
      label: "Education",
      domain_pack: "education",
      industry: "education",
      description: "Teachers, school admins, curriculum and student workflows"
    },
    %{
      id: "independent",
      label: "Independent Builder",
      domain_pack: "software",
      industry: "general",
      description: "Solo builders using AI agents without an engineering team"
    }
  ]

  @packs %{
    "software" => %{
      industry: "web",
      compliance: ["OWASP Top 10", "Secrets hygiene", "Cost guardrails"],
      stack_guidance:
        "Favor maintainable web stacks, small PR slices, explicit hosting choices, and rollback-safe delivery.",
      validation_language:
        "Treat auth, secrets, hosting, edge spend, and release rollback as first-class constraints.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who will use it first?",
          prompt: "Who are the first users and what job should this product do for them?",
          placeholder: "Founders, internal operators, customers, support staff..."
        },
        %{
          id: "data_involved",
          label: "What data is involved?",
          prompt: "What data, accounts, uploads, or records will the first release touch?",
          placeholder: "Customer records, auth data, payments, analytics, uploaded files..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 capabilities that must exist in the first working version.",
          placeholder: "Dashboard, approvals, exports, authentication, notifications..."
        },
        %{
          id: "constraints",
          label: "What constraints matter most?",
          prompt:
            "What limits matter most right now: budget, hosting, timeline, security, or review requirements?",
          placeholder: "$30/month, Railway deploy, launch in 2 weeks, human review before prod..."
        }
      ]
    },
    "healthcare" => %{
      industry: "health",
      compliance: ["HIPAA", "HITECH", "OWASP Top 10"],
      stack_guidance:
        "Prefer tightly hosted or local-first systems, encrypted storage, access controls, and immutable audit trails.",
      validation_language:
        "Assume PHI may be present unless clearly ruled out. Require auditable access, approval gates, and deployment caution.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses it in the care flow?",
          prompt:
            "Which staff or patients touch this workflow first, and where in the care or billing flow does it sit?",
          placeholder: "Front desk, billing specialists, clinic admins, patients..."
        },
        %{
          id: "data_involved",
          label: "What records are involved?",
          prompt:
            "What patient, insurance, scheduling, or health-related records are involved in the first release?",
          placeholder: "Patient names, insurance notes, appointment details, lab results..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 workflow steps that absolutely must work in the first safe release.",
          placeholder: "Intake, review, approval, export, audit logging..."
        },
        %{
          id: "constraints",
          label: "What safety limits matter?",
          prompt:
            "What constraints matter most around approvals, hosting, access control, or compliance review?",
          placeholder:
            "No public access, local hosting first, audit logs required, admin approval before deploy..."
        }
      ]
    },
    "education" => %{
      industry: "education",
      compliance: ["FERPA", "COPPA", "WCAG 2.1 AA"],
      stack_guidance:
        "Prefer accessible interfaces, clear permissions, student-data minimization, and reviewable release scope.",
      validation_language:
        "Assume accessibility and student-data handling matter from day one; keep workflows simple and auditable.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses it first?",
          prompt:
            "Which teachers, admins, students, or parents use the first version, and for what task?",
          placeholder: "Teachers managing curriculum, school admins, students submitting work..."
        },
        %{
          id: "data_involved",
          label: "What student data is involved?",
          prompt: "What student, classroom, or school records are involved in the first release?",
          placeholder: "Student names, lesson plans, progress notes, attendance..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 capabilities the first version must support for the classroom or admin workflow.",
          placeholder: "Lesson publishing, assignment workflow, approvals, exports..."
        },
        %{
          id: "constraints",
          label: "What limits matter most?",
          prompt:
            "What matters most right now around accessibility, moderation, device support, privacy, or budget?",
          placeholder: "WCAG support, low-cost hosting, teacher review before publish..."
        }
      ]
    }
  }

  @agent_options [
    {"claude", "Claude Code"},
    {"codex", "Codex CLI"},
    {"cursor", "Cursor"},
    {"bolt", "Bolt / Lovable"},
    {"replit", "Replit"},
    {"generic", "Other / custom agent"}
  ]

  def occupation_profiles, do: @occupation_profiles
  def agent_options, do: @agent_options

  def questions_for_occupation(occupation_id) do
    occupation_id
    |> occupation_profile()
    |> Map.fetch!(:domain_pack)
    |> pack()
    |> Map.fetch!(:questions)
  end

  def occupation_profile(id) do
    Enum.find(@occupation_profiles, &(&1.id == id)) || List.first(@occupation_profiles)
  end

  def pack(domain_pack), do: Map.fetch!(@packs, domain_pack)
  def packs, do: @packs

  def preflight_context(attrs) do
    occupation = occupation_profile(Map.get(attrs, "occupation"))
    pack = pack(occupation.domain_pack)
    content = content_blob(attrs)
    domain_pack = occupation.domain_pack

    %{
      occupation: occupation,
      domain_pack: domain_pack,
      industry: occupation.industry,
      preliminary_risk_tier: preliminary_risk_tier(domain_pack, content),
      compliance: pack.compliance,
      stack_guidance: pack.stack_guidance,
      validation_language: pack.validation_language
    }
  end

  def content_blob(attrs) do
    answers =
      Map.get(attrs, "interview_answers", %{})
      |> Map.values()
      |> Enum.join(" ")

    [Map.get(attrs, "idea", ""), answers]
    |> Enum.join(" ")
    |> String.downcase()
  end

  def preliminary_risk_tier("healthcare", content) do
    cond do
      String.contains?(content, ["patient", "medical", "insurance", "phi"]) -> "critical"
      true -> "high"
    end
  end

  def preliminary_risk_tier("education", content) do
    cond do
      String.contains?(content, ["student record", "child", "minor", "discipline"]) -> "high"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier(_domain_pack, content) do
    cond do
      String.contains?(content, [
        "payment",
        "billing",
        "salary",
        "admin",
        "authentication",
        "login"
      ]) ->
        "high"

      String.contains?(content, ["upload", "customer", "account", "personal"]) ->
        "moderate"

      true ->
        "moderate"
    end
  end
end
