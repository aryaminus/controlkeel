# Security Review Checklist

Use this checklist before task completion, proof approval, or release review.
Each item lists a concrete verification step. Run `ck_validate` for automated pattern
detection, then manually verify items that require architectural or process judgment.

## Baseline

- **Secrets**: Verify no hardcoded API keys, tokens, passwords, private keys, or connection strings exist in source code, config files, environment files, or test fixtures. Run `ck_validate` and confirm zero `security.hardcoded_secret` findings. Check that CI/CD secret management uses vault references, not plaintext values.
- **Injection (SQL)**: Verify all database queries use parameterized statements, Ecto-style bindings, or query builders. Search for string concatenation in SQL query construction. Run `ck_validate` and confirm zero `security.sql_injection` findings.
- **Injection (shell)**: Verify no shell commands are constructed by interpolating user input directly into command strings. Use argument arrays or validated allowlists instead. Run `ck_validate` and confirm zero `security.shell_injection` findings.
- **Injection (HTML/XSS)**: Verify no `innerHTML` assignments from untrusted input. Confirm Phoenix HEEx templates escape by default and any `raw` or `phx-no-curly-interpolation` usage is audited. Run `ck_validate` and confirm zero `security.xss` findings.

## Authentication and Authorization

- **Authentication on protected routes**: Verify every route that accesses user-scoped data requires authentication. Confirm middleware or plugs check session or token validity before controller action. Check that API endpoints validate bearer tokens against active, non-expired, non-revoked credentials.
- **Authorization checks**: Verify each protected endpoint checks the caller's role or scope before performing the action. Confirm ownership checks (user can only access their own resources) are enforced at the data layer, not just the UI layer. Check that admin-only endpoints are not reachable by non-admin tokens even with direct API calls.
- **Session management**: Verify session tokens expire within a reasonable timeframe. Confirm session invalidation on password change and logout. Check that concurrent session limits are enforced if applicable.
- **Service account controls**: Verify service accounts have scoped permissions (not blanket admin). Confirm service account tokens have short expiry and support revocation. Check that service account activity is logged.

## Input Validation and Output Encoding

- **Input validation**: Verify all user-supplied input is validated for type, length, format, and range before processing. Confirm file uploads are validated for type and size, and scanned for malware if applicable. Check that JSON/XML parsers are configured to reject oversized or malformed payloads.
- **Output encoding**: Verify all dynamic content rendered in HTML is contextually encoded (HTML body, attribute, JavaScript, URL). Confirm API responses use structured JSON, not string interpolation of user data. Check that error messages do not leak internal state, stack traces, or database details.
- **File handling**: Verify uploaded files are stored outside the web root. Confirm file paths are validated to prevent directory traversal. Check that file content types are verified by inspection, not just the client-supplied MIME type.

## API Security

- **CORS policy**: Verify CORS is not configured as `*` for authenticated endpoints. Confirm allowed origins are explicitly enumerated. Check that credential-bearing requests are not sent to overly broad origins.
- **Rate limiting**: Verify rate limiting is active on authentication, registration, and password-reset endpoints. Confirm rate limits are scoped per identity (not just per IP) where applicable. Check that rate-limit headers are not informative to attackers.
- **Request size limits**: Verify maximum request body size is configured and enforced. Confirm file upload size limits are applied at the reverse proxy and application level. Check that JSON payload depth is bounded.
- **TLS enforcement**: Verify all production endpoints redirect HTTP to HTTPS. Confirm HSTS headers are set. Check that TLS configuration follows current best practices (TLS 1.2+, strong cipher suites).

## Data Protection

- **Encryption at rest**: Verify sensitive data fields (PII, financial, health, credentials) are encrypted in the database. Confirm encryption keys are managed through a vault or KMS, not stored alongside the data. Check that key rotation is supported and documented.
- **Encryption in transit**: Verify all internal service-to-service communication uses TLS or equivalent. Confirm database connections use SSL. Check that external API calls use HTTPS and validate certificates.
- **Logging hygiene**: Verify no sensitive data (passwords, tokens, SSNs, card numbers, health data) appears in application logs. Confirm log levels in production do not emit debug data that includes request bodies with PII. Check that error tracking (Sentry, etc.) is configured to scrub sensitive fields.
- **Data masking in responses**: Verify API responses mask or omit sensitive fields for non-privileged scopes. Confirm pagination responses do not leak record counts that could enable enumeration attacks. Check that error responses do not include internal identifiers or stack traces.

## Dependency and Supply Chain

- **Dependency audit**: Verify all direct and transitive dependencies are at non-vulnerable versions. Run `ck_validate` or equivalent dependency scanner. Confirm a process exists for timely patching of critical CVEs. Check that dependency pinning is used in production builds.
- **Lock file integrity**: Verify lock files are committed and not modified without review. Confirm CI verifies lock file consistency. Check that dependency resolution does not silently upgrade versions.
- **Container image hygiene**: Verify base images are minimal and up-to-date. Confirm images do not run as root. Check that no unnecessary packages or shells are included in production images.

## Infrastructure and Deployment

- **Environment separation**: Verify production credentials are not used in development or staging environments. Confirm environment-specific configuration is loaded from vault or environment variables, not hardcoded. Check that test fixtures use synthetic data, not production data.
- **Secret rotation**: Verify database credentials, API keys, and signing keys are rotated on a defined schedule. Confirm rotation does not cause downtime. Check that old credentials are invalidated promptly after rotation.
- **Backup and recovery**: Verify backups are encrypted and access-controlled. Confirm backup restoration has been tested within the retention period. Check that backup data includes integrity checksums.
- **Infrastructure as code**: Verify all infrastructure changes go through version-controlled configuration (not manual console changes). Confirm infrastructure configuration is reviewed before application. Check that drift detection is active.

## Domain overlays

Apply the relevant domain-specific checks from [domain-review-matrix.md](../domain-audit/references/domain-review-matrix.md) in addition to the above.

- **Healthcare**: PHI access, encryption, minimum necessary, audit logging, breach process.
- **Finance**: card data isolation, tokenization, immutable financial records, segregation of duties.
- **Education**: student-record disclosure and age/consent requirements, FERPA compliance.
- **HR**: discriminatory criteria and employee/candidate PII exposure, compensation visibility.
- **Legal**: privilege handling, retention, and document protection, conflict checking.
- **Marketing/Sales/Real Estate**: consent, CRM PII, fair-housing constraints, contract handling.
- **Government**: records retention, benefits fairness, approval chain integrity.
- **Insurance**: claims fairness, medical-adjacent privacy, denial review.
- **E-commerce**: card scope, refund controls, fraud detection.
- **Logistics**: custody integrity, dispatch safety, carrier data protection.
- **Manufacturing**: QA holds, traceability, safety interlocks.
- **Nonprofit**: donor privacy, grant restrictions, beneficiary data protection.
