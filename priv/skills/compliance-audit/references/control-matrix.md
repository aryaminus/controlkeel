# Control Matrix

Use the session's active compliance profile to select the relevant section.
Each control lists a concrete check. Run `ck_validate` to scan for known patterns,
then manually verify items that require human judgment.

## Baseline

- **Secrets**: Verify no hardcoded API keys, tokens, passwords, or private keys exist in source code, config files, or logs. Run `ck_validate` and confirm zero `security.hardcoded_secret` findings.
- **Injection**: Verify SQL queries use parameterized statements or Ecto-style bindings. Verify shell commands avoid string interpolation of user input. Verify HTML templates escape dynamic content. Run `ck_validate` and confirm zero `security.sql_injection`, `security.shell_injection`, and `security.xss` findings.
- **XSS**: Verify no `innerHTML` assignments from untrusted input. Verify React/Phoenix templates escape by default. Check any dangerously-set HTML APIs.

## Healthcare

- **PHI encryption**: Confirm all stored PHI uses AES-256 or equivalent encryption at rest. Confirm all PHI in transit uses TLS 1.2+. Check database column-level encryption for diagnosis, treatment, and identifier fields.
- **Role-based access**: Verify every route or API endpoint that touches PHI checks the caller's role. Verify admin-only endpoints are not reachable by non-admin tokens. Check that audit logs record which role accessed which record.
- **Audit logging**: Confirm all PHI read/write operations produce an immutable log entry with timestamp, user/service identity, record ID, and action type. Verify logs are append-only and retained per HIPAA requirements (minimum 6 years).
- **Breach process**: Confirm a documented incident response plan exists for PHI breaches. Verify the plan includes notification timelines (60 days for covered entities). Check that breach detection triggers alerts to the compliance officer.
- **Minimum necessary**: Verify each access scope exposes only the minimum PHI fields required for the task. Confirm bulk export endpoints strip fields not needed by the consumer.

## Finance

- **No raw card data**: Verify no credit card numbers appear in logs, databases, error reports, or debug output. Confirm all card data flows through a PCI-DSS-compliant payment processor. Run `ck_validate` and check for `security.hardcoded_secret` patterns matching card-number formats.
- **Tokenization**: Verify stored payment references are processor tokens, not raw card numbers. Confirm token-to-card resolution only happens at the payment processor boundary.
- **Immutable financial records**: Confirm financial transaction rows use insert-only semantics. Verify no UPDATE or DELETE paths exist on transaction tables. Check that correction entries create new rows with reversal references rather than modifying existing records.
- **Segregation of duties**: Verify the same identity cannot both create and approve a financial transaction. Confirm approval workflows require a different user or service account than the initiator.
- **Audit trail**: Confirm every financial state change produces a signed, timestamped audit entry. Verify audit entries include before/after state for reconciliation.

## Education

- **Student-record disclosure**: Verify FERPA-compliant consent checks before any student data export. Confirm directory information opt-out is respected in all listing endpoints. Check that student IDs are not exposed in URLs or logs.
- **Age and consent checks**: Verify age-gating logic for accounts under 13 (COPPA). Confirm parental consent workflow is triggered before data collection for minors. Check that consent records are retained and auditable.
- **Access logging**: Confirm all student record access produces an audit log entry. Verify bulk access (e.g., instructor roster views) logs the scope of records accessed.

## HR

- **Candidate data segregation**: Verify candidate PII is stored separately from interview scoring data. Confirm hiring decision records reference scored rubrics, not raw candidate attributes. Check that rejected candidate data is retained per required retention periods and then purged.
- **No protected-attribute scoring**: Verify no model or scoring logic uses race, gender, age, religion, disability, or other protected attributes as input features. Confirm compensation algorithms use only role, level, geography, and experience. Run `ck_validate` on any scoring or ranking code.
- **Salary data access controls**: Verify compensation data is accessible only to roles with explicit need (HR ops, finance payroll). Confirm manager visibility is limited to direct reports. Check that salary fields are excluded from bulk export unless the caller has explicit compensation scope.

## Legal

- **Privilege isolation**: Verify attorney-client privileged documents are tagged and access-controlled to legal team only. Confirm privilege tags propagate to search indexes and export endpoints. Check that AI-generated summaries of privileged content do not leak into non-privileged contexts.
- **Encrypted documents**: Confirm legal documents are encrypted at rest with key management tied to legal team roles. Verify document sharing links expire and require authentication. Check that deleted documents are purged from backups within retention policy.
- **Retention schedule**: Verify document retention periods are configured per document type and jurisdiction. Confirm automated purge or archive runs respect legal-hold flags. Check that retention policy changes do not retroactively shorten holds on active matters.

## Marketing / Sales / Real Estate

- **Consent and unsubscribe**: Verify CAN-SPAM-compliant unsubscribe links in all marketing emails. Confirm unsubscribe requests take effect within 10 business days. Check that purchased lead lists include consent provenance metadata.
- **CRM or lead PII protection**: Verify CRM export endpoints strip or mask PII for non-authorized scopes. Confirm contact deletion requests propagate across all CRM integrations within the required timeframe (typically 30 days for GDPR). Check that lead scoring does not use sensitive attributes.
- **Fair-housing and tenant-data controls**: Verify property listing algorithms do not filter by protected neighborhood characteristics. Confirm tenant screening uses only legally permissible criteria. Check that tenant PII retention respects state-specific data destruction requirements.
