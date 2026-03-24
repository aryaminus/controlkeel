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



ok. now when using with any of the agents supports, does it need additional api keys to run ck? cant ck just run the agents llm to do things if needed? or doe sit have to have api keys or local llm? what if users dont have it? what if users just ask agents to do stuff? how do users even setup which provider to use? can agent have ck set globally by default or does it require them to setup always for every new repo/directory. make sure agetns can be fully uyse ck by themselves without humans having to act. 

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
CK can automate **low-risk** paths and surface **medium** risk; **destructive / high-risk** actions still expect policy-appropriate gates (approve/reject, proofs), not unbounded silent autonomy. Product stance is documented in onboarding/getting-started; full “zero human” for all risk tiers is not promised.

---

## Agent list note

The list above is a **research/backlog** of names. It is **not** a completion checklist for shipping (see `idea/missing/opencode.md` “Ignore For Now” / long-tail list).
