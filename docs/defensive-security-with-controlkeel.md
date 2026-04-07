# Defensive Security with ControlKeel

This guide explains the `security` domain pack and the defensive-security workflow CK now provides.

## What this is for

Use the `security` domain pack when the job is not generic app delivery, but a governed defender loop such as:

- appsec triage and remediation
- supply-chain and advisory handling
- detection-rule generation
- authorized reproduction in an isolated runtime
- disclosure packet and release gate preparation

CK is not positioning this as an offensive exploit automation product. The product shape is defense-first.

## Supported workflow

Security sessions use the `security_defender_v1` mission template and explicit phases:

1. discovery
2. triage
3. reproduction
4. patch
5. validation
6. disclosure

Those phases are stored on the task graph, surfaced in proof bundles, and used by the validation and delegation gates.

## Security occupations

The first-class security occupations are:

- `appsec_engineer`
- `security_researcher`
- `open_source_maintainer`
- `security_operations`

They differ mainly in their default posture:

- `appsec_engineer`: repo-first, patch-first, review-heavy
- `security_researcher`: stronger isolation requirements and verified-research defaults
- `open_source_maintainer`: disclosure-aware, patch-validation-heavy
- `security_operations`: telemetry and detection-rule workflow first

## Cyber access modes

CK now recognizes three internal dual-use modes:

- `standard`
- `defensive_security`
- `verified_research`

They are intentionally not equivalent.

### `standard`

This is the default for ordinary governed software work. It should not be used for reproduction-style security workflows.

### `defensive_security`

This is the default for most security-domain work. It allows defender workflows such as discovery, triage, patching, validation, and detection-rule generation, but it still blocks higher-risk reproduction-style work.

### `verified_research`

This is the high-trust mode for explicitly marked security-research sessions. CK still requires:

- non-unknown target scope
- stronger review expectations
- isolated runtime paths for reproduction-phase delegated execution

This is an internal control shape, not a public verification program.

## What `ck_validate` does for security work

`ck_validate` remains the main preflight tool. For security work it now accepts:

- `security_workflow_phase`
- `artifact_type`
- `target_scope`

It adds workflow-aware checks for:

- live-target ambiguity
- unsafe disclosure content
- exploit-chain escalation language
- missing patch-validation evidence
- unsupported authorization claims

It also preserves the earlier trust-boundary and destructive-shell protections.

## Vulnerability lifecycle metadata

CK does not create a separate vulnerability database in v1. It uses governed findings with a structured metadata contract for `category = security`.

Important fields include:

- `finding_family`
- `affected_component`
- `evidence_type`
- `exploitability_status`
- `patch_status`
- `disclosure_status`
- `cwe_ids`
- `cve_id`
- `maintainer_scope`
- `repro_artifact_ref`
- `patch_artifact_ref`
- `disclosure_due_at`

The important behavior is:

- proofs summarize vulnerability cases without embedding raw exploit payloads
- release readiness can block on unresolved critical vulnerability cases
- disclosure packets default to evidence references and redaction, not dangerous detail dumps

## Proof and release behavior

Security proof bundles include:

- vulnerability summary
- patch status
- disclosure state
- validation evidence reference
- redaction marker
- release gate decision

Release readiness treats unresolved critical vulnerability cases as blocking even when smoke and provenance are otherwise green.

## Benchmarks

The built-in defensive-security suites are:

- `vuln_patch_loop_v1`
- `detection_rule_gen_v1`
- `supply_chain_triage_v1`

These are defender workflow suites. They are not meant to claim parity with frontier zero-day discovery systems. They exist to measure whether CK is governing the remediation loop well:

- finding quality
- false positives
- patch correctness signals
- validation completeness
- proof completeness
- time and overhead
- rule and decision calibration

## Current non-goals

CK is not claiming:

- generic offensive exploit automation
- unrestricted live-target testing
- full black-box binary exploitation as a first-class attach flow
- public access to a cyber verification marketplace

Binary and endpoint evidence can be represented today through imported or shell-subject artifacts and isolated runtime paths, but not through fake broad native capability claims.
