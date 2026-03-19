---
name: compliance-audit
description: "Run a structured compliance audit against active ControlKeel policy packs (baseline, GDPR, HIPAA, PCI-DSS, FERPA, EEOC, CAN-SPAM, etc.). Use this before releasing any feature that handles personal data, payment information, health records, or regulated content."
license: Apache-2.0
metadata:
  author: controlkeel
  version: "1.0"
compatibility: Works with any MCP-capable agent. Pair with ck_validate and ck_finding tools.
---

# Compliance Audit Skill

## How to Run a Compliance Audit

1. Call `ck_context` to identify which policy packs are active for this session:
   ```
   ck_context({"session_id": <id>})
   ```
   Look at `compliance_profile` in the response to see active packs.

2. Run through the relevant checklist sections below.

3. For each failure, call `ck_finding` with the appropriate rule_id.

4. Produce a summary report: packs checked, items reviewed, pass/fail, blocking items.

---

## Baseline Pack (always active)

- [ ] `baseline.secrets` — No hardcoded credentials anywhere in the codebase
- [ ] `baseline.injection` — All SQL / shell / template injection vectors mitigated
- [ ] `baseline.xss` — All user output HTML-escaped

---

## GDPR Pack (EU data handling)

- [ ] `gdpr.consent` — Explicit user consent obtained before collecting personal data
- [ ] `gdpr.right_to_delete` — Deletion mechanism exists for user personal data
- [ ] `gdpr.data_minimization` — Only collecting data that is strictly necessary
- [ ] `gdpr.data_portability` — Users can export their data in a machine-readable format
- [ ] `gdpr.cross_border_transfer` — No cross-border data transfers without safeguards (SCCs, adequacy decision)
- [ ] `gdpr.breach_notification` — Process exists to notify supervisory authority within 72 hours of breach
- [ ] `gdpr.dpo_contact` — Data Protection Officer contact documented if required

---

## Healthcare Pack (HIPAA / HITECH)

- [ ] `healthcare.phi_encryption` — PHI encrypted at rest (AES-256) and in transit (TLS 1.2+)
- [ ] `healthcare.phi_access_control` — Role-based access control on all PHI records
- [ ] `healthcare.phi_audit_log` — All PHI access logged with user, timestamp, action
- [ ] `healthcare.minimum_necessary` — Minimum necessary standard applied to PHI exposure
- [ ] `healthcare.baa` — Business Associate Agreement in place with all PHI processors
- [ ] `healthcare.breach_notification` — HIPAA breach notification process documented

---

## Finance Pack (PCI-DSS / SOX)

- [ ] `finance.card_data_isolation` — No raw card data in application code or logs
- [ ] `finance.pci_tokenization` — Card data tokenized via PCI-compliant payment processor
- [ ] `finance.financial_records_immutable` — Financial records are append-only / immutable
- [ ] `finance.sox_audit_trail` — All financial transactions have an audit trail
- [ ] `finance.segregation_of_duties` — No single actor can approve and execute financial changes

---

## Education Pack (FERPA / COPPA)

- [ ] `education.student_records` — Student education records not disclosed without consent
- [ ] `education.coppa_age_check` — Age verification for users under 13; parental consent obtained
- [ ] `education.ferpa_access_log` — Access to student records logged

---

## HR Pack (EEOC / Employee PII)

- [ ] `hr.candidate_data` — Candidate personal data segregated from business data
- [ ] `hr.automated_screening` — No automated screening tools making final hiring decisions without human review
- [ ] `hr.salary_access` — Salary and compensation data access role-restricted
- [ ] `hr.discrimination_signals` — Protected class attributes not used in any scoring or filtering

---

## Legal Pack (Privilege / Retention)

- [ ] `legal.privilege_protection` — Attorney-client privileged communications isolated and access-controlled
- [ ] `legal.document_encryption` — Legal documents encrypted at rest
- [ ] `legal.retention_policy` — Document retention schedule implemented; auto-expiry in place

---

## Marketing Pack (CAN-SPAM / Consent)

- [ ] `marketing.opt_in` — Explicit opt-in before sending commercial email
- [ ] `marketing.unsubscribe` — Unsubscribe mechanism present in all emails; honoured within 10 days
- [ ] `marketing.sender_identity` — Sender name and physical address in all marketing emails
- [ ] `marketing.contact_list_security` — Contact lists encrypted; access logged

---

## Sales Pack (CRM / Contact PII)

- [ ] `sales.crm_access_control` — CRM contact records access role-restricted
- [ ] `sales.contact_deletion` — Contact deletion/export request mechanism implemented
- [ ] `sales.quota_audit_trail` — Quota and revenue data changes have an audit trail

---

## GDPR + California (CCPA)

- [ ] `ccpa.opt_out` — "Do Not Sell My Personal Information" mechanism present
- [ ] `ccpa.disclosure` — Privacy policy discloses categories of personal information sold
- [ ] `ccpa.deletion_request` — Deletion request process honours 45-day response window

---

## Reporting

After completing the audit, call `ck_finding` for each failure:

```
ck_finding({
  "session_id": <id>,
  "category": "compliance",
  "severity": "critical" | "high" | "medium",
  "rule_id": "<pack>.<rule_key>",
  "plain_message": "<what failed and why>",
  "decision": "block" | "warn" | "escalate_to_human"
})
```

Produce a final summary:
- Packs checked
- Total controls reviewed
- Controls passed / failed
- Blocking findings (requires human action before deploy)
- Recommended next steps
