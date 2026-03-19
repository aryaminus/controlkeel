# Security Review Checklist

Use this checklist before task completion or proof approval.

## Baseline

- Secrets are not hardcoded or logged.
- SQL, shell, and HTML injection vectors are mitigated.
- Unsafe DOM HTML writes are removed or sanitized.

## Software

- Authentication and authorization checks exist on protected routes.
- Dynamic code execution is avoided for untrusted input.
- CORS is not overly broad on authenticated flows.
- Sensitive data is masked in logs and responses.

## Domain overlays

- Healthcare: PHI access, encryption, minimum necessary, audit logging.
- Finance: card data isolation, audit trails, immutable financial records.
- Education: student-record disclosure and age/consent requirements.
- HR: discriminatory criteria and employee / candidate PII exposure.
- Legal: privilege handling, retention, and document protection.
- Marketing / sales / real estate: consent, CRM PII, fair-housing constraints.

