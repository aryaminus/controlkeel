hermes agent

rlm agent
gepa agent
dspy agent

deepagents
openswe 

Codestral

openclaw
claude dispatch

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

## Research name classification (honest scope)

Statuses: **`in_catalog`** — first-class `controlkeel attach <id>` in [`AgentIntegration.catalog/0`](../../lib/controlkeel/agent_integration.ex). **`covered_via_mcp_instructions`** — use MCP + instruction bundle path like OpenCode-class targets (often same as `mcp-plus-instructions`). **`proxy_only`** — govern only if the client can send traffic through ControlKeel’s [OpenAI/Anthropic proxy paths](../../docs/agent-integrations.md). **`not_planned_no_api`** — no stable attach hook in-repo today. **`duplicate_of`** — same as another row.

Canonical table of shipped targets: [docs/support-matrix.md](../../docs/support-matrix.md).

| Name / note | Status | Notes |
|-------------|--------|--------|
| hermes agent | not_planned_no_api | Research framework; no dedicated attach target. |
| rlm agent | not_planned_no_api | Research framework; no dedicated attach target. |
| gepa agent | not_planned_no_api | Research framework; no dedicated attach target. |
| dspy agent | not_planned_no_api | Research / library; no dedicated attach target. |
| deepagents | not_planned_no_api | Generic term; no single attach hook. |
| openswe | not_planned_no_api | No stable MCP/config contract in this repo. |
| Codestral | not_planned_no_api | Model/API family; use provider profile or proxy if your stack exposes compatible APIs. |
| openclaw | not_planned_no_api | No stable attach hook in this repo. |
| claude dispatch | duplicate_of | Use **`claude-code`** (`in_catalog`). |
| opencode | in_catalog | `opencode` |
| amp | in_catalog | `amp` |
| slate | not_planned_no_api | No stable attach hook in this repo. |
| cursor agent | duplicate_of | Use **`cursor`** (`in_catalog`). |
| droid | not_planned_no_api | No stable attach hook in this repo. |
| forge | not_planned_no_api | Ambiguous product name; no dedicated attach target. |
| t3code anything to pull for connections? | not_planned_no_api | No stable attach hook in this repo. |
| khadgi-sujan / retune | not_planned_no_api | External projects; not tracked as attach targets. |
| prd | not_planned_no_api | Document type, not a client. |
| requirement analysis | not_planned_no_api | Workflow, not a client. |

**Default for any MCP-capable editor not listed:** `covered_via_mcp_instructions` — register the ControlKeel MCP server per [getting-started.md](../../docs/getting-started.md) and use the same portable instruction bundle pattern as other `mcp-plus-instructions` targets.
