hermes agent

rlm agent
gepa agent
dspy agent

deepagents
openswe

Codestral

openclaw
claude dispatch

copilot cli


what about congnition, windsurf, codex app server, cline, ollama, vllm, sglang, lmstudio, fastmcp, huggingface, 

opencode

amp

slate

cursor agent

droid

forge

t3code anything to pull for connections?

khadgi-sujan / retune

prd
requirement analysis

ok. now when using with any of the agents supports, does it need additional api keys to run ck? cant ck just run the agents llm to do things if needed? or doe sit have to have api keys or local llm? what if users dont have it? what if users just ask agents to do stuff? how do users even setup which provider to use? can agent have ck set globally by default or does it require them to setup always for every new repo/directory. make sure agetns can be fully use ck by themselves without humans having to act.

---

## Answers (current product behavior)

These are the questions the paragraph above is asking. Short answers for docs/onboarding alignment:

**Does ControlKeel need extra API keys on top of the agent?**  
Not always. Resolution order includes: **agent bridge** (use the attached agent’s provider path where supported), **ControlKeel user/workspace profile** (stored key), **project override**, **local Ollama**, then **heuristic / no-LLM**. With no key and no bridge, CK still runs governance-oriented flows; **model-backed** compile/advisory features degrade. See onboarding provider panel and `docs/getting-started.md`.

**Can CK “just use the agent’s LLM”?**  
When **bridge** is active, guided compilation and similar features can follow the bridged provider. It is not universal magic across every agent; support class per agent is in `docs/agent-integrations.md` and `lib/controlkeel/agent_integration.ex`.

**What if the user has no API key and no local LLM?**  
**Heuristic mode**: governance, proofs, skills, benchmarks, MCP tooling can still matter; model-backed compilation and advisory are limited or fallback. The UI explains what degrades (see onboarding copy).

**How do users choose a provider?**  
Environment + CLI (`controlkeel` profile/attach), project binding under `controlkeel/`, and docs. Onboarding shows **current provider** and mode in plain language.

**Global vs every repo**  
Attachment/bootstrap can be **user-scoped** for some targets; **governed project binding** is **project-local** by design. So: global convenience where supported, not “one toggle replaces per-project governance.”

**Can agents use CK fully without humans?**  
CK can automate **low-risk** paths and surface **medium** risk; **destructive / high-risk** actions still expect policy-appropriate gates (approve/reject, proofs), not unbounded silent autonomy. Product stance is documented in onboarding/getting-started and [docs/autonomy-and-findings.md](../../docs/autonomy-and-findings.md); full “zero human” for all risk tiers is not promised.

---

## Agent list note

The list above is a **research/backlog** of names. It is **not** a completion checklist for shipping (see `idea/missing/opencode.md` “Ignore For Now” / long-tail list).

## Research name classification (typed support)

Support classes now replace the old catch-all `not_planned_no_api` label:

- **`attach_client`** — first-class `controlkeel attach <id>`
- **`headless_runtime`** — exported runtime bundle, not a local attach command
- **`framework_adapter`** — benchmark/policy/runtime adapter surface, not a local attach command
- **`provider_only`** — provider/profile template, not an attachable client
- **`alias`** — points to a canonical shipped integration
- **`unverified`** — no canonical official upstream contract was verified

Canonical inventory: [docs/support-matrix.md](../../docs/support-matrix.md).

| Name / note | Support class | Canonical id / mapping | Notes |
|-------------|---------------|------------------------|-------|
| hermes agent | attach_client | `hermes-agent` | Native skills + MCP companion; CK can reuse agent-owned provider config where Hermes exposes it. |
| rlm agent | unverified | `rlm-agent` | No canonical official upstream contract verified. |
| gepa agent | framework_adapter | `gepa` | Adapter surface for optimizer/policy-training workflows, not `attach`. |
| dspy agent | framework_adapter | `dspy` | Adapter surface for benchmark/programming workflows, not `attach`. |
| deepagents | framework_adapter | `deepagents` | Runtime harness adapter surface, not `attach`. |
| openswe | headless_runtime | `open-swe` | Repo/runtime export via `controlkeel runtime export open-swe`; uses `AGENTS.md` plus webhook/CI guidance. |
| Codestral | provider_only | `codestral` | Provider/profile template for Mistral Codestral-compatible APIs. |
| openclaw | attach_client | `openclaw` | Native skills + plugin bundle + MCP companion config. |
| claude dispatch | alias | `claude-dispatch -> claude-code` | Use Claude Code as the canonical shipped path. |
| copilot cli | alias | `copilot-cli -> copilot` | Repo-native Copilot attach; `copilot-plugin` covers CLI / VS Code agent mode. |
| opencode | attach_client | `opencode` | MCP + instructions bundle path. |
| amp | attach_client | `amp` | MCP + instructions bundle path. |
| slate | unverified | `slate` | No canonical official upstream contract verified. |
| cursor agent | alias | `cursor-agent -> cursor` | Use Cursor as the canonical shipped path. |
| droid | attach_client | `droid` | Factory Droid `.factory` bundle with skills, droids, commands, and MCP config. |
| forge | attach_client | `forge` | ACP-first companion export with MCP fallback. |
| t3code anything to pull for connections? | alias | `t3code -> codex-cli` | Wrapper path until a stable native contract is verified. |
| khadgi-sujan / retune | unverified | `retune` | External project; no canonical official attach contract verified. |
| prd | n/a | n/a | Document type, not a client. |
| requirement analysis | n/a | n/a | Workflow artifact, not a client. |

**Default for any MCP-capable editor not listed:** use the existing MCP + instruction bundle path described in [getting-started.md](../../docs/getting-started.md). That is a transport pattern, not a claim of first-class native support.

## Additional current-market audit

An official-doc audit of adjacent agent clients found one clear new first-class fit and two names that still need more stable upstream contracts before CK should promise native support.

| Name | Current CK status | Why |
|------|-------------------|-----|
| Cline | shipped `attach_client` (`cline`) | Official docs expose a stable MCP config path, project/global skills directories, and `.clinerules` / workflow locations, so CK can support it truthfully. |
| Roo Code | research only for now | Roo clearly supports MCP, but its repo-level modes/rules/config surface is still split across extension docs, repo structure, and cloud product docs. |
| Goose | research only for now | Goose has strong MCP extension docs, but CK does not yet ship a dedicated recipe / `.goosehints` companion target, so support remains the generic MCP path instead of a fake native attach. |
