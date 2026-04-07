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
    },
    %{
      id: "finance",
      label: "Finance / Fintech",
      domain_pack: "finance",
      industry: "finance",
      description: "Payments, accounting, reconciliation, financial operations"
    },
    %{
      id: "hr",
      label: "HR / Recruiting",
      domain_pack: "hr",
      industry: "hr",
      description: "Candidate screening, employee records, onboarding, performance workflows"
    },
    %{
      id: "legal",
      label: "Legal / Compliance",
      domain_pack: "legal",
      industry: "legal",
      description: "Matter management, document review, contracts, eDiscovery workflows"
    },
    %{
      id: "marketing",
      label: "Marketing / Content",
      domain_pack: "marketing",
      industry: "marketing",
      description: "Campaigns, email lists, consent flows, analytics, content operations"
    },
    %{
      id: "sales",
      label: "Sales / CRM",
      domain_pack: "sales",
      industry: "sales",
      description: "Pipeline tracking, contact management, quota reporting, deal workflows"
    },
    %{
      id: "realestate",
      label: "Real Estate",
      domain_pack: "realestate",
      industry: "realestate",
      description: "Listings, transactions, client intake, disclosure and compliance workflows"
    },
    %{
      id: "government",
      label: "Government / Public Sector",
      domain_pack: "government",
      industry: "government",
      description: "Permits, casework, constituent services, records, and benefits workflows"
    },
    %{
      id: "insurance",
      label: "Insurance / Claims",
      domain_pack: "insurance",
      industry: "insurance",
      description: "Claims intake, underwriting, servicing, and fraud review workflows"
    },
    %{
      id: "ecommerce",
      label: "E-commerce / Retail",
      domain_pack: "ecommerce",
      industry: "retail",
      description: "Orders, returns, catalog ops, fulfillment, and customer support workflows"
    },
    %{
      id: "logistics",
      label: "Logistics / Supply Chain",
      domain_pack: "logistics",
      industry: "logistics",
      description: "Dispatch, shipment tracking, warehouse operations, and carrier coordination"
    },
    %{
      id: "manufacturing",
      label: "Manufacturing / Quality",
      domain_pack: "manufacturing",
      industry: "manufacturing",
      description: "Production planning, QA, traceability, supplier, and plant workflows"
    },
    %{
      id: "nonprofit",
      label: "Nonprofit / Grants",
      domain_pack: "nonprofit",
      industry: "nonprofit",
      description: "Donor records, grant reporting, volunteer operations, and service delivery"
    },
    %{
      id: "appsec_engineer",
      label: "AppSec Engineer",
      domain_pack: "security",
      industry: "security",
      description:
        "Defensive code review, triage, patch validation, and secure release governance"
    },
    %{
      id: "security_researcher",
      label: "Security Researcher",
      domain_pack: "security",
      industry: "security",
      description:
        "Authorized reproduction, exploit-chain review, isolated runtime testing, and disclosure"
    },
    %{
      id: "open_source_maintainer",
      label: "Open Source Maintainer",
      domain_pack: "security",
      industry: "security",
      description:
        "Defender workflows for advisories, supply-chain triage, patches, and coordinated disclosure"
    },
    %{
      id: "security_operations",
      label: "Security Operations",
      domain_pack: "security",
      industry: "security",
      description:
        "Detection engineering, telemetry workflows, endpoint validation, and incident-driven hardening"
    }
  ]

  @supported_packs @occupation_profiles |> Enum.map(& &1.domain_pack) |> Enum.uniq()
  @pack_labels %{
    "software" => "Software",
    "healthcare" => "Healthcare",
    "education" => "Education",
    "finance" => "Finance",
    "hr" => "HR / Recruiting",
    "legal" => "Legal / Compliance",
    "marketing" => "Marketing / Content",
    "sales" => "Sales / CRM",
    "realestate" => "Real Estate",
    "government" => "Government / Public Sector",
    "insurance" => "Insurance / Claims",
    "ecommerce" => "E-commerce / Retail",
    "logistics" => "Logistics / Supply Chain",
    "manufacturing" => "Manufacturing / Quality",
    "nonprofit" => "Nonprofit / Grants",
    "security" => "Security / Defensive AppSec"
  }

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
    },
    "finance" => %{
      industry: "finance",
      compliance: ["PCI-DSS", "SOX", "OWASP Top 10", "AML/KYC basics"],
      stack_guidance:
        "Prefer isolated payment flows, immutable audit trails, double-entry reconciliation, and strict access controls. Never mix payment credentials with application code.",
      validation_language:
        "Treat every financial record as auditable and every credential as PCI-scoped. Require explicit approval gates before any transaction-path change ships.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who handles money in this flow?",
          prompt:
            "Which roles or customers touch financial data, and at what point in the transaction or reporting flow?",
          placeholder: "Finance team, customers paying invoices, accountants reconciling..."
        },
        %{
          id: "data_involved",
          label: "What financial data is involved?",
          prompt:
            "What payment, ledger, reconciliation, or account records are involved in the first release?",
          placeholder:
            "Invoice totals, card payment intents, bank feeds, salary records, tax data..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 financial operations the first version must handle reliably and auditably.",
          placeholder:
            "Invoice generation, payment capture, reconciliation report, approval workflow..."
        },
        %{
          id: "constraints",
          label: "What compliance limits apply?",
          prompt:
            "What constraints apply around PCI scope, data residency, approval thresholds, or audit requirements?",
          placeholder:
            "No card data in logs, EU data residency, CFO approval before prod, full audit trail..."
        }
      ]
    },
    "hr" => %{
      industry: "hr",
      compliance: ["EEOC", "GDPR / CCPA (employee PII)", "SOC 2"],
      stack_guidance:
        "Minimize employee PII storage, enforce role-based access, and treat all candidate data as privacy-scoped. Separate screening logic from final hiring decisions.",
      validation_language:
        "Assume all candidate and employee records contain PII. Require audit trails for screening, promotion, and termination workflows. Flag any automated decision-making on candidate data.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses this in the hiring or HR flow?",
          prompt:
            "Which HR team members, hiring managers, or candidates interact with the first version, and at what stage of the workflow?",
          placeholder:
            "Recruiters screening candidates, hiring managers reviewing, employees updating profiles..."
        },
        %{
          id: "data_involved",
          label: "What employee or candidate data is involved?",
          prompt:
            "What personal, performance, or employment records are touched in the first release?",
          placeholder:
            "Candidate CVs, interview notes, salary bands, performance reviews, employment contracts..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 HR or recruiting operations the first version must support.",
          placeholder:
            "Job posting, application intake, interview scheduling, offer letter, onboarding checklist..."
        },
        %{
          id: "constraints",
          label: "What compliance or access limits apply?",
          prompt:
            "What constraints matter most around candidate data privacy, bias prevention, approval chains, or retention policy?",
          placeholder:
            "GDPR right-to-erasure, no automated rejection, manager approval before offer, 2-year retention..."
        }
      ]
    },
    "legal" => %{
      industry: "legal",
      compliance: ["Attorney-client privilege", "Data retention policy", "eDiscovery readiness"],
      stack_guidance:
        "Encrypt all documents at rest and in transit. Implement matter-scoped access controls — no cross-matter data leakage. Never log document content; log access metadata only.",
      validation_language:
        "Treat all matter records and communications as potentially privileged. Require approval gates before any external integrations or document exports. Assume everything is discoverable.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who in the firm or legal team uses this?",
          prompt:
            "Which attorneys, paralegals, clients, or staff interact with the first version, and for which matter type?",
          placeholder:
            "Associates drafting contracts, partners reviewing, clients submitting documents..."
        },
        %{
          id: "data_involved",
          label: "What legal records or documents are involved?",
          prompt:
            "What matter files, communications, contracts, or discovery records are in scope for the first release?",
          placeholder:
            "Contract drafts, client correspondence, discovery documents, court filings, billing records..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 legal workflow steps the first version must handle safely.",
          placeholder:
            "Matter intake, document upload, review workflow, client portal, billing time entry..."
        },
        %{
          id: "constraints",
          label: "What privilege or retention limits apply?",
          prompt:
            "What matters most around privilege protection, retention schedules, access controls, or external sharing?",
          placeholder:
            "No external cloud for privileged docs, 7-year retention, client sign-off before export..."
        }
      ]
    },
    "marketing" => %{
      industry: "marketing",
      compliance: ["GDPR", "CAN-SPAM", "CCPA", "Brand safety basics"],
      stack_guidance:
        "Prefer explicit consent flows, double opt-in lists, and unsubscribe-first architecture. Isolate contact records from analytics pipelines and never cross-reference PII without documented consent.",
      validation_language:
        "Treat all contact records as consent-scoped. Require proof of opt-in before any send. Flag analytics that cross-reference PII without a documented legal basis.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who manages or receives this marketing?",
          prompt:
            "Which marketers, content editors, or recipients interact with the first version?",
          placeholder:
            "Email marketers, social media managers, campaign analysts, newsletter subscribers..."
        },
        %{
          id: "data_involved",
          label: "What contact or audience data is involved?",
          prompt:
            "What subscriber, campaign, or analytics data is in scope for the first release?",
          placeholder:
            "Email lists, open/click analytics, customer segments, ad targeting data, social handles..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 marketing operations the first version must support.",
          placeholder:
            "Campaign builder, send scheduling, audience segmentation, unsubscribe handling, analytics..."
        },
        %{
          id: "constraints",
          label: "What consent or brand limits apply?",
          prompt:
            "What matters most around data consent, unsubscribe compliance, brand review, or channel restrictions?",
          placeholder:
            "Double opt-in required, GDPR consent proof, brand review before send, no purchased lists..."
        }
      ]
    },
    "sales" => %{
      industry: "sales",
      compliance: ["GDPR / CCPA (CRM data)", "SOC 2", "Data portability"],
      stack_guidance:
        "Treat CRM records as portable and deletable from day one. Never hard-code quota logic — it belongs in config. Isolate pipeline data from billing data and keep contact sync reversible.",
      validation_language:
        "Assume every CRM record contains personal contact data subject to deletion requests. Require data portability from day one. Flag quota calculations that are audit-sensitive or bias-adjacent.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who manages the sales pipeline?",
          prompt:
            "Which sales reps, managers, or ops staff use the first version, and at which stage of the sales cycle?",
          placeholder:
            "Account executives logging deals, SDRs managing leads, sales ops pulling reports..."
        },
        %{
          id: "data_involved",
          label: "What CRM or deal data is involved?",
          prompt:
            "What contact records, pipeline stages, activity logs, or revenue data are in scope?",
          placeholder:
            "Lead profiles, deal stages, call notes, quota attainment, contract values, email history..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 sales operations the first version must support.",
          placeholder:
            "Lead import, pipeline view, activity logging, quota dashboard, deal handoff..."
        },
        %{
          id: "constraints",
          label: "What data privacy or access limits apply?",
          prompt:
            "What matters most around contact deletion, data export, quota audit, or CRM integration security?",
          placeholder:
            "GDPR delete-on-request, no PII in analytics exports, manager-only quota view, SSO required..."
        }
      ]
    },
    "realestate" => %{
      industry: "realestate",
      compliance: ["Fair Housing Act basics", "RESPA basics", "GDPR / CCPA (client PII)"],
      stack_guidance:
        "Handle property and client data with PII-first mindset. Avoid storing SSN, financial disclosures, or sensitive inspection data in unencrypted logs. Keep listing data separate from transaction records.",
      validation_language:
        "Treat all client property transactions as PII-adjacent. Require consent before sharing listing data with third-party portals. Flag any automated screening that could violate Fair Housing rules.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses this in the property transaction flow?",
          prompt:
            "Which agents, clients, admins, or lenders interact with the first version, and at which stage?",
          placeholder:
            "Buyer's agents managing listings, clients submitting offers, transaction coordinators..."
        },
        %{
          id: "data_involved",
          label: "What property or client records are involved?",
          prompt:
            "What listing data, client profiles, transaction documents, or financial disclosures are in scope?",
          placeholder:
            "MLS listings, buyer/seller profiles, purchase agreements, inspection reports, title docs..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 real estate workflow steps the first version must support.",
          placeholder:
            "Listing intake, offer submission, document upload, transaction timeline, client portal..."
        },
        %{
          id: "constraints",
          label: "What compliance or access limits apply?",
          prompt:
            "What matters most around Fair Housing compliance, document encryption, MLS data rules, or client consent?",
          placeholder:
            "No discriminatory screening, encrypted docs, MLS data not publicly shared, GDPR consent..."
        }
      ]
    },
    "government" => %{
      industry: "government",
      compliance: [
        "Public records retention",
        "Section 508 accessibility",
        "Sensitive citizen data handling"
      ],
      stack_guidance:
        "Favor auditable workflows, records retention, accessibility, and explicit approval checkpoints. Treat case files, permits, and benefits data as review-heavy and retention-bound from day one.",
      validation_language:
        "Assume every citizen-facing workflow is subject to records requests, retention rules, and public accountability. Flag record deletion, protected-class scoring, and unreviewed case exports aggressively.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses this public-sector workflow?",
          prompt:
            "Which caseworkers, permitting staff, citizens, or admins use the first version, and for what public service workflow?",
          placeholder:
            "Permit reviewers, licensing clerks, benefits staff, residents submitting requests..."
        },
        %{
          id: "data_involved",
          label: "What constituent or case data is involved?",
          prompt:
            "What permit, case, benefits, or resident records will the first release handle?",
          placeholder:
            "Permit applications, case notes, addresses, benefit eligibility records, inspection history..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 government workflow steps the first version must support safely and auditably.",
          placeholder: "Application intake, routing, approval, record export, status updates..."
        },
        %{
          id: "constraints",
          label: "What records or accessibility limits apply?",
          prompt:
            "What matters most around retention schedules, accessibility, review chains, or export controls?",
          placeholder:
            "7-year retention, Section 508 conformance, supervisor sign-off before publish, no bulk public export..."
        }
      ]
    },
    "insurance" => %{
      industry: "insurance",
      compliance: ["Claims auditability", "GLBA basics", "NAIC privacy expectations"],
      stack_guidance:
        "Keep claims, underwriting, and servicing flows auditable and role-scoped. Separate medical or protected-condition data from broad operational logs and never automate denial logic on sensitive traits.",
      validation_language:
        "Treat policyholder and claimant data as privacy-scoped and dispute-sensitive. Flag denial logic based on protected or medical attributes, unencrypted claims exports, and missing review steps.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who works in the claims or policy flow?",
          prompt:
            "Which adjusters, underwriters, policyholders, or servicing staff use the first release?",
          placeholder:
            "Claims adjusters, underwriters, policyholders uploading docs, service reps..."
        },
        %{
          id: "data_involved",
          label: "What policyholder or claim data is involved?",
          prompt:
            "What claim, policy, payment, or medical-adjacent data is in scope for the first release?",
          placeholder:
            "Claim notes, policy numbers, payout amounts, diagnosis summaries, beneficiary details..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 insurance operations the first version must support.",
          placeholder:
            "Claim intake, triage, document upload, reserve approval, payment tracking..."
        },
        %{
          id: "constraints",
          label: "What privacy or approval limits apply?",
          prompt:
            "What matters most around denial review, sensitive-attribute handling, access control, or retention?",
          placeholder:
            "Human sign-off before denial, no diagnosis in logs, adjuster-only claim notes, retention by policy line..."
        }
      ]
    },
    "ecommerce" => %{
      industry: "retail",
      compliance: ["PCI-DSS", "Consumer privacy", "Returns / fraud controls"],
      stack_guidance:
        "Keep checkout, refunds, and customer support flows isolated and reversible. Never log full payment credentials or session tokens, and keep catalog ops separate from payments and account recovery.",
      validation_language:
        "Treat carts, orders, and customer profiles as fraud-sensitive and privacy-scoped. Flag full-card logging, unsafe refund automation, and data joins that expose customer history broadly.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses the storefront or ops flow?",
          prompt:
            "Which shoppers, support staff, or operations teams use the first version, and for which commerce task?",
          placeholder:
            "Customers checking out, support reviewing returns, merch ops editing catalog..."
        },
        %{
          id: "data_involved",
          label: "What order or customer data is involved?",
          prompt:
            "What order, payment, catalog, or account data is touched in the first release?",
          placeholder:
            "Order totals, payment intents, shipping addresses, return reasons, loyalty profiles..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 commerce operations the first version must support.",
          placeholder:
            "Catalog publish, checkout, order status, returns workflow, fraud review..."
        },
        %{
          id: "constraints",
          label: "What payments or fraud limits apply?",
          prompt:
            "What matters most around card scope, refund approval, privacy, or fraud review?",
          placeholder:
            "No PAN in logs, manager approval for refunds, delete-on-request for accounts, manual review above threshold..."
        }
      ]
    },
    "logistics" => %{
      industry: "logistics",
      compliance: ["Chain of custody", "Safety / dispatch review", "Vendor access control"],
      stack_guidance:
        "Keep shipment state, dispatch actions, and carrier data auditable and append-only where possible. Avoid deleting movement history and require review for safety or hazmat overrides.",
      validation_language:
        "Treat routing, custody, and delivery records as operationally critical. Flag deletion of shipment history, unsafe dispatch overrides, and excessive exposure of driver or consignee data.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses this logistics workflow?",
          prompt:
            "Which dispatchers, warehouse staff, drivers, or customers interact with the first version?",
          placeholder:
            "Dispatch coordinators, warehouse leads, drivers, customer support tracing shipments..."
        },
        %{
          id: "data_involved",
          label: "What shipment or carrier data is involved?",
          prompt: "What shipment events, route data, inventory, or driver records are in scope?",
          placeholder:
            "Tracking scans, manifests, pickup windows, warehouse counts, driver phone numbers..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 logistics operations the first version must support.",
          placeholder:
            "Dispatch, tracking updates, exception handling, warehouse receiving, proof of delivery..."
        },
        %{
          id: "constraints",
          label: "What safety or retention limits apply?",
          prompt:
            "What matters most around custody history, safety checks, carrier access, or deletion policy?",
          placeholder:
            "No deletion of scan history, supervisor approval for hazmat override, driver PII restricted..."
        }
      ]
    },
    "manufacturing" => %{
      industry: "manufacturing",
      compliance: ["Quality traceability", "Change control", "Plant safety review"],
      stack_guidance:
        "Prefer traceable work-order, QA, and supplier workflows with sign-off steps. Keep production overrides reviewable and never bypass quality holds or safety interlocks in automation.",
      validation_language:
        "Treat QA, recall, and plant-safety workflows as high-impact. Flag safety interlock bypasses, unsigned quality overrides, and missing lot traceability.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who works in the production flow?",
          prompt:
            "Which planners, operators, QA staff, or suppliers use the first version and for which workflow?",
          placeholder:
            "Production planners, line operators, QA inspectors, maintenance leads, supplier managers..."
        },
        %{
          id: "data_involved",
          label: "What production or quality data is involved?",
          prompt:
            "What work orders, lot traces, inspection results, or supplier records are in scope?",
          placeholder:
            "Lot IDs, QA checkpoints, equipment status, supplier batches, maintenance logs..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 manufacturing or quality operations the first version must support.",
          placeholder:
            "Work-order intake, QA sign-off, lot trace, maintenance requests, supplier holds..."
        },
        %{
          id: "constraints",
          label: "What safety or traceability limits apply?",
          prompt:
            "What matters most around change control, traceability, operator permissions, or recall readiness?",
          placeholder:
            "No bypassing QA hold, operator-only changes, recall traceability required, supervisor sign-off for overrides..."
        }
      ]
    },
    "nonprofit" => %{
      industry: "nonprofit",
      compliance: ["Donor privacy", "Grant audit trails", "Volunteer / beneficiary safeguards"],
      stack_guidance:
        "Treat donor, volunteer, and beneficiary records as privacy-scoped and audit-sensitive. Keep grant restrictions explicit, and separate fundraising workflows from service-delivery records.",
      validation_language:
        "Assume grant, donor, and beneficiary data requires minimization and review. Flag sensitive exports, donor payment logging, and grant-spend automation without restrictions or approvals.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who uses this nonprofit workflow?",
          prompt:
            "Which fundraisers, program staff, volunteers, donors, or beneficiaries use the first version?",
          placeholder:
            "Development staff, grant managers, volunteers, donor ops, case managers..."
        },
        %{
          id: "data_involved",
          label: "What donor, grant, or beneficiary data is involved?",
          prompt: "What donation, grant, volunteer, or service-delivery records are in scope?",
          placeholder:
            "Donation history, grant restrictions, volunteer background data, beneficiary case notes..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt: "List the 3-5 nonprofit operations the first version must support.",
          placeholder:
            "Donation intake, grant tracking, volunteer scheduling, beneficiary intake, compliance reporting..."
        },
        %{
          id: "constraints",
          label: "What privacy or grant limits apply?",
          prompt:
            "What matters most around donor privacy, grant restrictions, beneficiary safeguards, or review requirements?",
          placeholder:
            "No donor card data in logs, grant approval before reallocation, beneficiary export locked down..."
        }
      ]
    },
    "security" => %{
      industry: "security",
      compliance: [
        "Coordinated disclosure",
        "Authorized target scope",
        "Patch validation evidence",
        "Supply-chain review"
      ],
      stack_guidance:
        "Prefer repo-local discovery, typed validation artifacts, isolated runtimes for reproduction, and proof-backed patching. Treat disclosure state, authorization scope, and rollback evidence as first-class constraints.",
      validation_language:
        "This is a defender workflow, not an offensive automation track. Require explicit scope, artifact references, redaction by default, and release readiness that accounts for unresolved vulnerability cases.",
      questions: [
        %{
          id: "who_uses_it",
          label: "Who owns this workflow?",
          prompt:
            "Which defenders, maintainers, or responders use this first, and what defensive security job are they trying to complete?",
          placeholder:
            "AppSec engineers triaging code, maintainers fixing advisories, detection engineers writing rules..."
        },
        %{
          id: "data_involved",
          label: "What assets are in scope?",
          prompt:
            "What repositories, binaries, telemetry, advisories, or evidence artifacts does the first workflow touch?",
          placeholder:
            "Source repo, SBOM, binary crash report, detection telemetry, disclosure draft..."
        },
        %{
          id: "first_release",
          label: "What must the first release do?",
          prompt:
            "List the 3-5 defensive workflow steps that must work in the first governed version.",
          placeholder:
            "Discovery, triage, patch planning, validation, disclosure packet, release gate..."
        },
        %{
          id: "constraints",
          label: "What safety limits apply?",
          prompt:
            "What matters most around authorization scope, isolated runtimes, disclosure timing, proof, or review requirements?",
          placeholder:
            "Owned repo only, isolated runtime for repro, redacted proofs, maintainer sign-off before disclosure..."
        }
      ]
    }
  }

  @agent_options [
    # Local IDEs (MCP attach supported)
    {"claude", "Claude Code"},
    {"cursor", "Cursor"},
    {"windsurf", "Windsurf"},
    {"kiro", "Kiro (Amazon)"},
    {"augment", "Augment Code"},
    {"amp", "Amp (Sourcegraph)"},
    # Local CLIs (MCP attach supported)
    {"aider", "Aider"},
    {"opencode", "OpenCode"},
    {"codex-cli", "Codex CLI"},
    {"gemini-cli", "Gemini CLI"},
    {"antigravity", "Antigravity"},
    {"continue", "Continue"},
    {"ollama", "Ollama (local)"},
    # Cloud scaffolders / platforms
    {"bolt", "Bolt"},
    {"lovable", "Lovable"},
    {"replit", "Replit"},
    {"v0", "v0 (Vercel)"},
    {"factory", "Factory"},
    {"devin", "Devin"},
    {"ai-studio", "Google AI Studio"},
    {"codex", "OpenAI Codex"},
    # LLM providers
    {"openai", "OpenAI"},
    {"anthropic", "Anthropic"},
    {"gemini", "Google Gemini"},
    {"deepseek", "DeepSeek"},
    {"mistral", "Mistral AI"},
    {"openrouter", "OpenRouter"},
    {"glm", "Zhipu GLM"},
    {"kimi", "Kimi (Moonshot)"},
    {"qwen", "Qwen (Alibaba)"},
    # Cloud managed LLM (enterprise IAM auth)
    {"bedrock", "AWS Bedrock"},
    {"vertex-ai", "Google Vertex AI"},
    {"azure-openai", "Azure OpenAI"},
    {"cohere", "Cohere"},
    # Fast / cheap inference APIs
    {"groq", "Groq Cloud"},
    {"together", "Together AI"},
    {"huggingface", "Hugging Face Inference"},
    {"replicate", "Replicate"},
    # Code review & spec tools
    {"copilot", "GitHub Copilot"},
    {"coderabbit", "CodeRabbit"},
    {"qodo", "Qodo"},
    {"specpilot", "SpecPilot"},
    {"chatprd", "ChatPRD"},
    {"specced", "Specced"},
    # Orchestration frameworks
    {"crewai", "CrewAI"},
    {"langchain", "LangChain"},
    {"deepagents", "DeepAgents"},
    {"nemo-guardrails", "NeMo Guardrails"},
    {"langgraph", "LangGraph"},
    {"autogen", "Microsoft AutoGen"},
    {"semantic-kernel", "Semantic Kernel"},
    {"dspy", "DSPy"},
    {"haystack", "Haystack"},
    {"dify", "Dify"},
    {"flowise", "Flowise"},
    {"n8n", "n8n"},
    {"prefect", "Prefect"},
    {"mastra", "Mastra"},
    # Managed agent platforms
    {"bedrock-agents", "AWS Bedrock Agents"},
    {"azure-ai-agent", "Azure AI Agent Service"},
    {"vertex-ai-agent", "Vertex AI Agent Builder"},
    # Workflow automation
    {"zapier", "Zapier"},
    {"make", "Make (Integromat)"},
    # Observability & prompt ops
    {"agentops", "AgentOps"},
    {"vellum", "Vellum"},
    {"promptflow", "Azure Prompt Flow"},
    {"generic", "Other / custom agent"}
  ]

  def occupation_profiles, do: @occupation_profiles
  def agent_options, do: @agent_options
  def supported_packs, do: @supported_packs

  def supported_pack?(value) when is_atom(value), do: supported_pack?(Atom.to_string(value))
  def supported_pack?(value) when is_binary(value), do: value in @supported_packs
  def supported_pack?(_value), do: false

  def normalize_pack(value, default \\ "software")

  def normalize_pack(value, default) when is_atom(value) do
    normalize_pack(Atom.to_string(value), default)
  end

  def normalize_pack(value, default) when is_binary(value) do
    pack = String.downcase(String.trim(value))
    if supported_pack?(pack), do: pack, else: default
  end

  def normalize_pack(_value, default), do: default

  def industry_for_pack(domain_pack) do
    domain_pack
    |> normalize_pack()
    |> pack()
    |> Map.fetch!(:industry)
  end

  def pack_label(domain_pack) do
    domain_pack
    |> normalize_pack()
    |> then(&Map.get(@pack_labels, &1, String.capitalize(&1)))
  end

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

  def pack(domain_pack), do: domain_pack |> normalize_pack() |> then(&Map.fetch!(@packs, &1))
  def packs, do: @packs

  def preflight_context(attrs) do
    occupation = occupation_profile(Map.get(attrs, "occupation"))
    pack = pack(occupation.domain_pack)
    content = content_blob(attrs)
    domain_pack = occupation.domain_pack

    %{
      occupation: occupation,
      domain_pack: domain_pack,
      domain_pack_label: pack_label(domain_pack),
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

  def preliminary_risk_tier("finance", content) do
    cond do
      String.contains?(content, ["card", "pci", "payment", "transaction", "bank"]) -> "critical"
      String.contains?(content, ["invoice", "reconciliation", "ledger", "salary"]) -> "high"
      true -> "high"
    end
  end

  def preliminary_risk_tier("hr", content) do
    cond do
      String.contains?(content, ["salary", "termination", "performance", "discrimination"]) ->
        "high"

      String.contains?(content, ["candidate", "application", "resume", "hiring"]) ->
        "high"

      true ->
        "moderate"
    end
  end

  def preliminary_risk_tier("legal", content) do
    cond do
      String.contains?(content, ["privilege", "discovery", "litigation", "confidential"]) ->
        "critical"

      String.contains?(content, ["contract", "matter", "client", "document"]) ->
        "high"

      true ->
        "high"
    end
  end

  def preliminary_risk_tier("marketing", content) do
    cond do
      String.contains?(content, ["pii", "gdpr", "consent", "personal data"]) -> "high"
      String.contains?(content, ["email list", "contact", "subscriber"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("sales", content) do
    cond do
      String.contains?(content, ["revenue", "quota", "commission", "salary"]) -> "high"
      String.contains?(content, ["crm", "contact", "lead", "pipeline"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("realestate", content) do
    cond do
      String.contains?(content, ["ssn", "financial disclosure", "tax", "mortgage"]) -> "high"
      String.contains?(content, ["client", "transaction", "offer", "listing"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("government", content) do
    cond do
      String.contains?(content, ["ssn", "benefits", "juvenile", "case file", "license"]) ->
        "critical"

      String.contains?(content, ["permit", "constituent", "inspection", "public record"]) ->
        "high"

      true ->
        "moderate"
    end
  end

  def preliminary_risk_tier("insurance", content) do
    cond do
      String.contains?(content, ["diagnosis", "claim denial", "underwriting", "beneficiary"]) ->
        "critical"

      String.contains?(content, ["claim", "policy", "adjuster", "premium", "payout"]) ->
        "high"

      true ->
        "moderate"
    end
  end

  def preliminary_risk_tier("ecommerce", content) do
    cond do
      String.contains?(content, ["card", "cvv", "refund", "chargeback", "checkout"]) -> "high"
      String.contains?(content, ["order", "cart", "customer", "return", "catalog"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("logistics", content) do
    cond do
      String.contains?(content, ["hazmat", "customs", "driver", "chain of custody"]) -> "high"
      String.contains?(content, ["shipment", "dispatch", "warehouse", "delivery"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("manufacturing", content) do
    cond do
      String.contains?(content, ["safety interlock", "recall", "lot trace", "quality hold"]) ->
        "high"

      String.contains?(content, ["work order", "supplier", "qa", "production"]) ->
        "moderate"

      true ->
        "moderate"
    end
  end

  def preliminary_risk_tier("nonprofit", content) do
    cond do
      String.contains?(content, ["donor card", "beneficiary", "minor", "tax receipt"]) -> "high"
      String.contains?(content, ["grant", "donor", "volunteer", "program"]) -> "moderate"
      true -> "moderate"
    end
  end

  def preliminary_risk_tier("security", content) do
    cond do
      String.contains?(content, [
        "exploit",
        "reproduction",
        "kernel",
        "binary",
        "privilege escalation"
      ]) ->
        "critical"

      String.contains?(content, ["triage", "patch", "disclosure", "detection", "advisory"]) ->
        "high"

      true ->
        "high"
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
