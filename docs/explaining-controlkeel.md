# Explaining ControlKeel

This document is the plain-English answer to:

- what is ControlKeel?
- why does it exist?
- what problem does it solve?
- how do you use it?
- how does it work?
- what makes it different from hosts, agents, IDEs, plugins, or post-hoc code review tools?

## The shortest explanation

**ControlKeel is the control plane for agent-generated software delivery.**

It does not try to be the coding model, IDE, or chat interface. It sits around the agent loop and adds the parts that usually break first in real work:

- reviewability
- scoped execution
- validation before risky actions
- findings and approval gates
- proofs and audit history
- budget and provider control
- task continuity and resume context
- release readiness

In one line:

**Agents generate output. ControlKeel turns that output into governed, reviewable, production-minded delivery.**

## The problem ControlKeel solves

Modern coding agents are very good at producing code, shell commands, plans, and edits.

They are much less reliable at:

- staying inside a real trust boundary
- knowing when a command is too destructive
- preserving enough context to be reviewable later
- proving what happened
- adapting their behavior to compliance, approval, or release risk
- keeping cost and provider behavior under control
- working consistently across many hosts and agent products

Without a layer like ControlKeel, the usual pattern is:

1. the host gives the model tools
2. the agent edits files and runs commands
3. humans hope the behavior was safe and correct
4. only after the fact do people try to reconstruct what happened

That is fine for toy work. It gets shaky fast for real repos, regulated work, shared teams, and expensive or high-risk changes.

ControlKeel exists because **agent capability is not the same thing as delivery safety**.

## The value proposition

ControlKeel gives you a governed agent workflow without replacing the agent you already like.

The main value is:

- **Safer execution**: CK validates risky code, config, text, and shell content before it becomes action.
- **Better context**: CK gives agents grounded repo, task, proof, and workspace context instead of relying on giant prompts or vague memory.
- **Reviewability**: CK turns work into findings, review packets, approvals, and proof bundles that humans can inspect.
- **Cross-host consistency**: CK gives a stable governance loop across hosts like Claude Code, Codex CLI, OpenCode, Copilot, Cline, Windsurf, Continue, and others.
- **Production orientation**: CK is about shipping safely, not just generating code quickly.
- **Recovery path**: even if another tool already changed the repo, CK can bootstrap into the project and bring the work back into a governed loop.
- **Managed decomposition**: CK keeps the manager layer explicit by recording how work is split, where review gates sit, and which steps are effectively delegated, recursive, or evidence-gated.
- **Explicit harness policy**: CK derives the operational policy around the work too: which tool classes can run concurrently, how compaction should step down, which failures need in-loop recovery paths, and what isolation delegated mutation should require.
- **Owned memory**: CK keeps durable state in typed memory, proofs, traces, and resume packets that you can inspect and carry across hosts instead of treating provider-managed session state as the system of record.

For defensive security teams, the same value proposition becomes:

- CK keeps vulnerability work inside an explicit detect-triage-patch-validate-disclose loop.
- CK defaults to redacted disclosure and proof-backed patch validation.
- CK distinguishes normal governed coding from higher-risk reproduction work with cyber access modes.
- CK stays defense-first; it does not present itself as a generic exploit automation product.

## What ControlKeel is not

ControlKeel is not:

- another foundation model
- another IDE
- a prompt marketplace
- a generic “AI assistant” shell wrapper
- a fake universal integration that claims to deeply support every host
- only a code scanner
- only a code review bot

It is specifically the **governance and delivery layer above generators**.

## How to explain it to someone in one minute

You can say:

> ControlKeel is the layer that sits between coding agents and production work. It does not replace Claude Code, Codex, OpenCode, or Copilot. It governs them. It gives agents bounded context, validates risky work, records findings, drives approvals, stores proof bundles, tracks budgets and providers, and keeps work reviewable across hosts. The point is not “more AI.” The point is making agent work safe enough, traceable enough, and structured enough to actually ship.

CK also makes the operating model explicit: it tells you whether a session is effectively advise-only, supervised, guarded autonomy, or long-running outcome work, and whether the current goal is task delivery or a KPI.
It also now derives a task augmentation brief so agents start from a scoped, reviewable problem frame instead of a vague ticket alone.

## How people use ControlKeel

The normal flow is:

1. install ControlKeel
2. bootstrap the repo with `controlkeel setup`
3. attach a supported host with `controlkeel attach <host>`
4. let the host use CK through local MCP, native skills, plugins, hooks, commands, or runtime bundles
5. inspect status, findings, proofs, and review state through the CLI or web app

Typical commands:

```bash
controlkeel setup
controlkeel attach opencode
controlkeel status
controlkeel findings
controlkeel proofs
controlkeel help
```

Typical web surfaces:

- `/start` for onboarding and execution brief creation
- `/missions/:id` for Mission Control and approvals
- `/findings` for governed findings
- `/proofs` for proof bundles
- `/ship` for release readiness and outcome metrics
- `/skills` for host/install/export compatibility

## How ControlKeel works

At a high level, CK runs a governed lifecycle around agent work:

1. **Intent intake**
   The user describes the work.

2. **Execution brief**
   CK compiles the practical boundary: risk tier, constraints, compliance, open questions, and delivery posture.

3. **Execution posture**
   CK decides how the work should be approached:
   - read-only virtual workspace first for discovery
   - typed memory/proofs/traces for durable state
   - typed or code-mode runtimes when large API/tool surfaces make that better
   - shell as the fallback mutation surface, with stronger approval pressure

4. **Runtime recommendation**
   CK recommends the best available attach/runtime path based on the brief and what is already attached or configured in the workspace.

5. **Task graph and routing**
   CK turns work into task state, routing hints, and reviewable progress.

   CK also derives a decomposition layer for that graph: node type, context strategy, depth, and review requirements. That gives both humans and hosts a shared view of how the work is being managed, not only what the task titles happen to be.

6. **Validation**
   CK validates code, config, shell, and text through `ck_validate`, FastPath, Semgrep, optional advisory review, trust-boundary checks, and destructive-operation tripwires.

7. **Findings and approvals**
   CK records governed findings, human gate hints, and review decisions.

8. **Proof capture**
   CK creates proof bundles so the final state is inspectable later.

9. **Ship metrics and benchmarks**
   CK tracks readiness, outcomes, and comparative evidence.

For `security` sessions, CK makes that lifecycle explicit:

- discovery
- triage
- reproduction
- patch planning
- patch validation
- disclosure and release readiness

## What the agent actually sees

When an agent uses ControlKeel, it does not just get “more prompt.”

It gets governed tools and structured context such as:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_budget`
- `ck_route`
- `ck_delegate`
- skill discovery and skill loading
- proof, memory, and review state

That means the agent can:

- ask CK for the current task and workspace context
- validate risky content before execution
- record findings instead of hiding them
- check budgets and routing
- use CK-native skills and hooks
- operate with resume context and proof continuity

This is very different from a host giving the agent raw shell and hoping it behaves.

## What makes ControlKeel different

### 1. It governs the delivery layer, not just the prompt

Most tools help an agent produce output.

ControlKeel helps you govern:

- whether the output should be trusted
- whether the action should run
- what proof exists
- what review state exists
- whether the work is actually ready to ship

### 2. It keeps support claims honest

Many tools blur together:

- native integration
- prompt compatibility
- “works if you manually copy this file somewhere”
- “maybe you can point it at an endpoint”

ControlKeel keeps those separate. It models hosts as typed integration rows with support classes such as:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

That matters because not every host actually supports the same things.

### 3. It supports agents and hosts in both directions

ControlKeel is not only “host uses CK.”

It also supports “CK runs or routes agent work” through:

- attach flows
- runtime exports
- provider brokerage
- hosted MCP
- A2A
- delegated execution

So the relationship is two-way:

- **agents use CK** for context, validation, findings, budgets, review, and skills
- **CK uses agents** for execution, routing, and host-specific runtime paths

### 4. It gives you typed durable state beyond files

Files matter, but they are not the whole story.

CK keeps durable state in typed surfaces such as:

- memory
- proof bundles
- traces
- outcomes
- checkpoints
- review packets

That makes the work resumable and auditable in a way most hosts do not provide natively.

### 5. It adds real trust-boundary behavior

ControlKeel explicitly models:

- trusted vs mixed vs untrusted content
- hidden instruction channels
- skill and plugin trust boundaries
- high-impact action escalation
- destructive shell tripwires

A host may expose tools. That does not mean it gives you a real governance model for those tools.

### 6. It is built for project rescue too

Even if another agent or tool already touched the repo, CK still helps by:

- bootstrapping the project
- surfacing findings
- reconstructing context
- validating risky content
- restoring review and proof flow

That rescue path is one of the most practically important differences.

## What hosts or agents usually do not provide

A host may provide:

- a chat UI
- tool calling
- file editing
- shell execution
- browser automation
- a native review UI
- its own memory or session history

But hosts usually do **not** provide the full ControlKeel layer in a portable, cross-host way.

What they often do not provide, or do not provide consistently, is:

- a portable governance loop across multiple agent hosts
- a typed support model that says what is truly supported and how
- repo-local proof bundles
- cross-host policy and findings continuity
- stable, explicit trust-boundary modeling
- strong destructive-op validation before execution
- budget governance and provider brokerage independent of one host
- typed resume packets and workspace reacquisition context
- a clean distinction between attach-native, runtime-export, provider-only, and fallback-governance modes

This is the key point:

**The host is usually optimized for using an agent. ControlKeel is optimized for governing agent work.**

## Why this matters even when the host is good

Even strong hosts still optimize for their own environment.

That leaves gaps if you care about:

- moving across hosts
- governing several kinds of agents
- keeping the same delivery rules in every repo
- preserving evidence and review state outside one vendor UI
- attaching new hosts without rewriting your entire workflow

ControlKeel gives you that portability and governance continuity.

## Who ControlKeel is for

The clearest users are:

- serious solo builders shipping with agents
- tiny agent-heavy teams
- people using more than one host or agent product
- teams that need reviewability, proofs, and release discipline
- teams working in higher-risk domains
- people who want a rescue path when another tool already changed the repo

It is especially useful when the problem is no longer “can the model write code?” and is now:

- “can we trust what just happened?”
- “can we review this?”
- “can we prove this?”
- “can we resume this later?”
- “can we ship this safely?”

## Who the customer is

There are a few customer layers:

- **Primary user**: the developer or operator running agent-heavy work in a real repo
- **Team buyer**: the small team lead who wants consistency, approvals, and proof without building an internal governance stack from scratch
- **Higher-trust buyer**: teams in domains where approval, evidence, or constraints matter more than raw speed

The product is strongest today for serious individuals and small teams rather than “big centralized enterprise admin suite first.”

## Why someone would choose ControlKeel instead of only using a host

Because hosts are excellent at being hosts, but they are not neutral control planes.

Choose ControlKeel when you want:

- the same governance loop across different hosts
- a clear support contract
- structured context and validation
- proofs and findings that live with the governed project
- safer behavior around risky execution
- runtime/provider flexibility
- a way to bring messy agent work back into a reviewable state

## The simplest mental model

If the coding agent is the engine, ControlKeel is the flight control layer.

If the host is the cockpit, ControlKeel is the system making sure the aircraft is still inside the approved envelope.

If the model writes the code, ControlKeel governs the path from idea to safe delivery.

## The practical takeaway

If you only need code generation, you may not need ControlKeel.

If you need:

- governed execution
- validation before risky actions
- cross-host consistency
- findings, approvals, and proofs
- resumable task state
- delivery and ship discipline

then that is exactly what ControlKeel is for.
