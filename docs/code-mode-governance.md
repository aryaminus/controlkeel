# Code-mode and generated-script governance

Large API surfaces should not become hundreds or thousands of always-loaded MCP tools. ControlKeel prefers progressive discovery first, then typed/code-mode execution when an agent needs to orchestrate many API endpoints without filling the transcript with unused tool schemas.

## Product stance

Code-mode is a compact plan format, not an automatic permission grant. Generated code, mini-scripts, and programmatic tool-calling snippets are treated as untrusted artifacts until CK validation and review approve the capabilities they need.

CK's current contract is advisory and policy-oriented:

- discover capabilities progressively instead of dumping full API surfaces into context
- describe large API interactions through typed SDKs or schemas when available
- run generated code only in an isolated runtime or host sandbox
- deny filesystem, shell, secrets, deploy, and network by default
- grant network only through reviewed allowlists and rate policy
- capture generated source, capability grants, runtime logs, egress summary, and result digests as proof artifacts

## CodeModePolicy

`ControlKeel.Runtime.CodeModePolicy` provides the code-backed policy map used by execution posture and future runtime exports. It currently records:

- `sandbox_required`
- `approval_required`
- `default_denied_capabilities`
- `allowed_capabilities`
- `network_allowlist`
- runtime and output limits
- rate policy with `respect_retry_after`
- proof artifacts expected from the runtime

`CodeModePolicy` does **not** execute code. It is consumed by `ck_execute_code`, which is intentionally narrow and refuses local host execution.

## `ck_execute_code`

`ck_execute_code` is the guarded MCP execution surface for generated code. It supports `dry_run` for planning and executes only through the Docker sandbox adapter when Docker is explicitly available. Local host execution is blocked because CK cannot make local `node`, `python`, or shell evaluation honor the default-deny filesystem/network/secrets contract.

Current execution constraints:

- supported languages: `javascript` and `python`
- supported execution sandbox: `docker` only
- network requests and network allowlists are still blocked until an enforcing egress proxy/runtime exists
- filesystem, secrets, shell, and deploy capabilities are always denied
- source is passed through `ck_validate` before execution
- runtime and output size are bounded
- output is truncated before returning to the agent

This gives users an executable path when they have a real sandbox configured, while keeping default installs safe through npm, Homebrew, GitHub Releases, and shell installers.

## Operating checklist

Before accepting generated code-mode output:

1. Confirm the brief actually needs code-mode or a large typed API surface.
2. Use progressive discovery (`ck_skill_list`, `ck_skill_load`, resources, typed API docs) before loading detailed schemas.
3. Run `ck_validate` on generated source and requested capabilities.
4. Require explicit approval for network, write APIs, deploy, shell, secrets, high-risk, or regulated data.
5. Keep concurrency and runtime bounded.
6. Respect `retry-after` and provider/API rate-limit telemetry.
7. Persist proof artifacts so saved mini-scripts can be revalidated before reuse.
