---
name: security-review
description: "Run a structured security review of code, configuration, or architecture against OWASP Top 10, baseline policy pack rules (secrets, injection, XSS), and domain-specific compliance requirements. Use this before marking any task done in a governed session."
license: Apache-2.0
metadata:
  author: controlkeel
  version: "1.0"
compatibility: Designed for Claude Code, Cursor, Kiro, and any repo-editing agent
---

# Security Review Skill

Use this skill to perform a structured security review before completing a task or opening a pull request. It maps directly to ControlKeel's baseline and software policy pack rules.

## Review Checklist

### 1. Secrets and Credentials (baseline pack)
- [ ] No hardcoded API keys, passwords, tokens, or secrets in any file
- [ ] No `.env` files committed with real values
- [ ] All secrets loaded from environment variables or a vault
- [ ] No credentials in logs or error messages

### 2. Injection (baseline pack — OWASP A03)
- [ ] All SQL queries use parameterized statements or ORM (no string interpolation)
- [ ] No shell command construction from user input
- [ ] No dynamic LDAP or XPath queries from user data
- [ ] Template rendering uses auto-escaping

### 3. XSS (baseline pack — OWASP A03)
- [ ] All user-controlled output is HTML-escaped before rendering
- [ ] No `innerHTML`, `dangerouslySetInnerHTML`, or `document.write` with user data
- [ ] Content-Security-Policy header is set

### 4. Authentication and Authorization (software pack)
- [ ] Authentication flows reviewed; no bypass patterns
- [ ] Authorization checks on every protected route/endpoint
- [ ] Session tokens are HttpOnly, Secure, SameSite
- [ ] Password hashing uses bcrypt, argon2, or equivalent (never MD5/SHA1)

### 5. Dynamic Code Execution (software pack)
- [ ] No `eval()`, `exec()`, `Function()`, or equivalent with untrusted input
- [ ] No deserialization of untrusted data without validation

### 6. CORS (software pack)
- [ ] No wildcard `Access-Control-Allow-Origin: *` on authenticated endpoints
- [ ] CORS origins are explicitly allowlisted

### 7. File Upload (when applicable)
- [ ] File type validated server-side (not just by extension)
- [ ] Upload size limits enforced
- [ ] Files stored outside web root or in object storage with signed URLs

### 8. Dependency Security
- [ ] No known CVE packages in direct dependencies
- [ ] Lock files committed and reproducible

### 9. Data Exposure (OWASP A02)
- [ ] Sensitive fields masked in API responses (passwords, tokens, SSNs)
- [ ] Error responses don't expose stack traces or internal paths

### 10. Logging and Monitoring
- [ ] Security-relevant events are logged (auth failures, access denied)
- [ ] Logs do not contain PII or secrets

## How to Run the Review

1. Call `ck_validate` with the code under review:
   ```
   ck_validate({"content": <code>, "kind": "code", "session_id": <id>})
   ```

2. For each checklist item that fails, call `ck_finding`:
   ```
   ck_finding({
     "session_id": <id>,
     "category": "security",
     "severity": "high",
     "rule_id": "security.auth.bypass",
     "plain_message": "Authentication check missing on /admin endpoint",
     "decision": "block"
   })
   ```

3. Report a summary to the human with: total items reviewed, pass/fail count, and any blocking findings.

## Severity Guide

| Issue Type | Severity |
|-----------|----------|
| Hardcoded secret, SQL injection, auth bypass | critical |
| XSS, open CORS, eval with user input | high |
| Missing rate limiting, weak session config | medium |
| Verbose error messages, missing security headers | low |
