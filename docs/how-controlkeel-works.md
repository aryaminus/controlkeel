# How ControlKeel Works

This document explains **how ControlKeel works in detail**, not just what it is.

It is meant for readers who want the exact operating model:

- how CK turns user intent into governed execution
- how CK interacts with hosts and agents
- how CK exposes context and validation
- how CK records review state, findings, and proofs
- how CK differs from a host, IDE, or raw MCP server

If you want the shorter product explanation first, read [explaining-controlkeel.md](explaining-controlkeel.md).

## The core idea

ControlKeel is a **control plane above generators**.

That means:

- the coding agent still writes code, plans, shell commands, or tool calls
- the host still provides the primary user interface
- the repo still contains the code and git state
- but CK manages the **governed delivery loop** around that work

CK does this by adding five things most agent hosts do not provide as one portable system:

1. a structured understanding of the work boundary
2. a governed tool and context surface for agents
3. validation and review gates around risky work
4. durable evidence and resumable task state
5. a typed integration model across many hosts and runtimes

It now also has a first-class **defensive security workflow** layered on top of that same chassis. CK does not create a separate security product surface. It reuses the same sessions, tasks, findings, proofs, validation, delegation, and release gates, but gives `security` sessions explicit phase structure and dual-use controls.

## The full lifecycle

In current product terms, CK runs this lifecycle:

1. intent intake
2. execution brief compilation
3. execution posture compilation
4. runtime recommendation compilation
5. task graph and routing
6. validation and findings
7. proof capture
8. ship metrics
9. comparative benchmark evidence
10. autonomy and improvement loop summaries

For `security` domain work, the lifecycle becomes:

1. discovery
2. triage
3. reproduction
4. patch
5. validation
6. disclosure and release readiness

That lifecycle is not just a pitch. It maps directly to the code-backed architecture and the main product surfaces.

## Step 1: intent intake

CK starts by turning user-supplied information into a normalized input model.

The important idea is that ControlKeel is **occupation-first and delivery-first**, not “pick a compliance acronym first.”

It asks:

- what kind of work is this?
- what domain does it belong to?
- what constraints matter?
- what data is involved?
- what delivery risk does this imply?

That is surfaced through the intent layer. The public entry point is [intent.ex](/Users/aryaminus/Developer/idea/lib/controlkeel/intent.ex).

The intent layer does not directly run agents. It compiles meaning:

- supported domain packs
- occupation profiles
- interview questions
- preflight context
- execution brief
- execution posture
- runtime recommendation
- boundary summary

This is important because CK does not start from “what tool can the model call?” It starts from “what kind of delivery boundary are we in?”

## Step 2: execution brief compilation

The execution brief is CK’s normalized summary of the work.

It is the first stage where vague human input becomes a governed artifact. The brief describes things like:

- risk tier
- likely domain pack
- constraints
- compliance expectations
- launch context
- open questions

The brief is later consumed by:

- Mission Control
- boundary summaries
- execution posture
- runtime recommendation
- task planning
- routing

This matters because CK keeps the **boundary** explicit instead of letting it stay hidden in a prompt.

For security work, the execution brief also carries:

- the `security` domain pack
- a defender-oriented mission template
- the default `cyber_access_mode`
- disclosure redaction defaults
- explicit release gating for vulnerability cases

## Step 3: execution posture compilation

Execution posture is how CK decides **what kind of execution surface is appropriate**.

This is not the same thing as “which agent should I use?”

It answers:

- should the work begin in read-only discovery?
- should durable state live in files, or in typed proof/memory/traces?
- should the work prefer typed/code-mode runtime over raw shell?
- when should shell still be allowed?
- how much approval pressure should exist?

The current execution posture model is explicitly built around these principles:

- use the read-only virtual workspace first for discovery
- keep durable state in typed surfaces such as memory, proofs, traces, and outcomes
- prefer typed or code-mode execution for large API or MCP-style tool surfaces
- keep shell as the fallback mutation surface
- escalate approval pressure as work moves toward broad or destructive authority

This is one of CK’s biggest philosophical differences from many hosts:

- hosts often begin from “the model has tools”
- CK begins from “the work has a posture and a boundary”

## Step 4: runtime recommendation compilation

After execution posture, CK derives a **runtime recommendation**.

This is where CK moves from abstract posture to a real path such as:

- use an attach-first host with stronger review surfaces
- use a headless runtime export
- use a configured or attached runtime path already present in the workspace

The recommendation is not generic. It is grounded in:

- the brief
- the posture
- the typed integration catalog
- currently attached agents
- runtime bundles already exported into the workspace
- provider/runtime signals

This means CK can say something much stronger than “use a sandbox.”

It can say:

- this work is review-heavy, so use an attach-first host
- this work is API-heavy and code-mode friendly, so a typed runtime is the better fit
- this workspace already has a usable attached or configured surface, so prefer that

This is a practical difference from many systems that only reason in the abstract.

CK now also derives a harness policy layer alongside that recommendation.

That policy makes the control-plane assumptions explicit:

- read-only discovery tools can be parallelized
- mutations stay serialized
- tool execution is expected to happen inside the main loop, not as an untracked afterthought
- context compaction should run hierarchically, cheapest first
- major error classes need named in-loop recovery paths
- delegated mutation should prefer isolated worktrees or equivalent governed runtimes

This is important because “posture” and “policy” are different things.

Posture answers:

- which surfaces should this session prefer?

Policy answers:

- how should the loop behave when it is under pressure?
- what can run concurrently?
- what gets compacted first?
- what recovery path is expected when things fail?
- what isolation standard should delegated work meet?

## Step 5: task graph and routing

Once the work is understood, CK turns it into governed task state.

This includes:

- sessions
- tasks
- task status
- task graph state
- decomposition summaries
- review state
- checkpoints
- resume packets
- routing hints

This is where ControlKeel moves from “understanding the work” to “operating the work.”

The practical effect is:

- work becomes resumable
- progress becomes inspectable
- review can happen against task state, not just raw diffs
- agents can reacquire context without pretending they remember everything
- recursive or delegated slices can be understood as governed nodes, not invisible prompt tricks

Mission Control is the UI expression of this layer, but the underlying state also feeds:

- CLI flows
- MCP tools
- hosted protocol access
- agent execution and delegation

## Step 6: governed context for agents

This is one of the most important parts of the system.

CK does not primarily help agents by pasting more context into prompts. It gives them **governed tools and typed context surfaces**.

The most important one is `ck_context`.

`ck_context` returns session-bound context such as:

- findings summary
- budget summary
- boundary summary
- current task
- planning context
- proof summary
- memory hits
- resume packet
- workspace snapshot
- workspace cache key
- context reacquisition signals
- recent transcript events
- transcript summary
- provider status

This makes the agent’s context:

- bounded
- session-aware
- workspace-aware
- resumable
- explicit

That is very different from letting an agent infer the state of the world from raw chat history or from repeated shell exploration alone.

CK now also derives a **task augmentation** artifact inside `ck_context`. It is not a separate execution engine. It is a derived contextual brief built from:

- the current task and session objective
- workspace context and repo instruction files
- recent hotspots and large-file signals
- active findings
- boundary constraints

The point is to make vague work more executable before the main run loop starts, without stuffing the entire repo into model context.

## How CK keeps context grounded

CK resolves workspace context from governed state, not only from process-local assumptions.

For example:

- runtime context can attach a `project_root`
- workspace resolution can look at the governed session binding
- MCP callers can provide a `project_root` hint
- but governed session/runtime state wins when CK already knows the right workspace

That matters because the same governed session should not appear differently depending on which host or working directory touched it.

## Step 7: validation before risky action

CK’s validation loop is centered on `ck_validate`.

This is one of the core product surfaces because it is where proposed work is checked before it becomes action.

`ck_validate` accepts:

- code
- config
- shell
- text

It also accepts structured trust-boundary metadata such as:

- `source_type`
- `trust_level`
- `intended_use`
- `requested_capabilities`
- `session_id`
- `task_id`
- `domain_pack`

Internally, validation is layered.

### Layer 1: FastPath

FastPath is the first deterministic validation layer.

It combines:

- pattern rules
- entropy checks
- budget findings
- trust-boundary findings
- destructive shell tripwires

This is where CK catches things like:

- secrets
- obvious injection patterns
- domain-specific policy problems
- unsafe trust-boundary crossings
- broad destructive shell operations

Recent destructive-shell protection is a good example of how CK governs execution rather than only reviewing code after the fact.

Repo-wide commands such as:

- `git checkout -- .`
- `git restore .`
- `git reset --hard`
- `git clean -fd`
- broad `rm -rf`

are blocked with recovery guidance, checkpoint hints, and rollback hints.

### Layer 2: Semgrep

If the content looks code-like and Semgrep is available, CK adds Semgrep findings to the decision.

### Layer 3: advisory review

If a provider is configured, CK can add an advisory review layer on top of deterministic findings.

That layer is explicit, not magical.

The result always states whether advisory ran or was skipped.

### Validation result

The final result includes:

- allowed or blocked decision
- summary
- normalized findings
- optional fix prompts
- advisory status

This is the public contract that hosts and agents see.

## Why validation is central to CK

Many agent systems assume:

- the model can reason well enough
- the host permissions are enough
- the human can catch issues later

CK does not assume that.

Instead it treats validation as a **first-class control surface**.

That is why validation is exposed consistently through:

- local CLI flows
- local MCP
- hosted MCP
- A2A-adjacent interop
- web surfaces

## Step 8: findings and review gates

If validation or governance identifies a problem, CK turns it into a governed finding.

A finding is not just a warning string. It has state.

Typical properties include:

- rule id
- category
- severity
- decision
- status
- human gate hints
- task/session linkage
- metadata

This lets CK treat review as part of the delivery system instead of as detached commentary.

Review state can then be:

- opened
- blocked
- escalated
- approved
- denied
- tracked through review packets and browser review flows

This is how CK creates a bridge between:

- machine-detected issues
- human approval workflows
- later evidence and proof state

## Step 9: proof bundles and durable evidence

Once work progresses or completes, CK captures proof.

Proof bundles are important because they answer:

- what happened?
- what was reviewed?
- what was validated?
- what findings existed?
- what was the rollback guidance?
- was the task actually deploy-ready?

Proof is one of the strongest differences between CK and many hosts.

Hosts may show chat history or diffs.

CK stores:

- proof bundles
- resume packets
- transcript summaries
- workspace snapshots
- memory records
- outcomes
- checkpoints

This lets the system remain useful after the original chat session is gone.

## Step 10: ship metrics and benchmarks

CK does not stop at “the agent finished.”

It tracks:

- ship readiness
- deploy-ready proof state
- outcome metrics
- benchmark evidence
- comparative runs

This is where CK shifts from “agent assistant” territory into “delivery control plane” territory.

The final question is not only:

- did the agent write code?

It is also:

- is this work ready to ship?
- what evidence supports that?
- how did this compare to other runs?

## The host model

A big part of how CK works is its host model.

CK does not pretend every host is the same.

Instead it uses a typed integration catalog with support classes such as:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

Each row also models things such as:

- how the agent uses CK
- how CK runs the agent
- execution support
- review experience
- runtime transport
- auth owner
- package outputs
- confidence level

This matters because “supports host X” is meaningless unless you say **how**.

CK’s model is explicit about whether support comes from:

- native attach
- plugin
- hooks
- rules
- workflows
- hosted MCP
- A2A
- runtime export
- provider-only path
- fallback governance

## How agents use CK

The “agent uses CK” direction includes surfaces like:

- local MCP
- hosted MCP
- A2A
- plugins
- native skills
- rules
- workflows
- hooks

This means the host agent can call back into CK for:

- context
- validation
- findings
- budgeting
- routing
- delegation
- memory
- proof-aware continuity

This is what makes CK usable **by agents**, not just around them.

## How CK runs agents

The reverse direction is equally important.

CK can operate agents through:

- `embedded`
- `handoff`
- `runtime`
- `none`

The practical meanings are:

- `embedded`: CK can launch a locally verifiable command/runtime path itself
- `handoff`: CK prepares the governed package and hands off to the host
- `runtime`: CK talks to a headless or remote runtime
- `none`: the agent may use CK, but CK does not drive it directly

This is the other half of the system architecture:

- agents use CK
- CK can also route or execute through agents where truthful

## Provider brokerage

CK also resolves provider access independently of any one host.

Provider resolution can come from:

1. attached agent bridge
2. workspace or service-account profile
3. user default profile
4. project override
5. local Ollama
6. heuristic fallback

This means CK can still function when:

- the host has no documented bridge
- the host uses its own internal auth model
- the user wants CK-owned provider control
- the user wants a local or OpenAI-compatible backend
- no provider is available and heuristic mode is required

This independence is important because governance and delivery should not disappear just because one host’s provider path is opaque.

## Hosted and local protocol surfaces

CK exposes both local and hosted protocol layers.

### Local stdio MCP

This is the normal repo-local path for attached clients.

### Hosted MCP

This is for service-account and remote usage.

Hosted MCP exposes a governed subset of tools under scoped authorization.

### Minimal A2A

This gives agent-card discovery and narrow message dispatch for external agent systems.

The important thing is that these transports all expose the **same governed model**, not entirely different products.

## Why CK is not “just an MCP server”

Because MCP is only one transport layer.

CK also includes:

- project bootstrap
- attach flows
- typed host catalog
- provider broker
- task graph
- review state
- proof bundles
- routing
- benchmarks
- ship metrics
- runtime exports
- plugin and skill generation

MCP is the access surface, not the whole system.

## Why CK is not “just a review tool”

Because review is only one stage.

CK also does:

- intent compilation
- posture compilation
- runtime recommendation
- task continuity
- validation before action
- governed execution/delegation
- proof capture
- ship readiness

## Why CK is not “just a wrapper around one host”

Because the product is intentionally designed to outlive any one host.

CK keeps:

- support typed and explicit
- host-specific surfaces honest
- governance portable
- proofs and findings outside one vendor UI
- runtime and provider control independent where needed

That is why it can attach to many hosts, export runtime bundles, and still provide fallback governance when native attach does not exist.

## How CK handles unsupported or partially supported tools

This is another important part of how it works exactly.

CK does **not** require universal native integration to be useful.

For unsupported tools, the honest path is:

1. bootstrap the governed project
2. let the external tool operate
3. use `controlkeel watch`, findings, proofs, and `ck_validate`
4. use proxy or provider-compatible endpoints when the tool supports them

This is why CK’s support story is more credible than systems that say “everything is supported” without explaining the mechanism.

## The main product surfaces

The product is expressed through several major surfaces.

### CLI

The CLI handles:

- bootstrap
- attach
- provider configuration
- status
- findings
- proofs
- review flows
- skill install/export
- runtime export
- task/session run
- host doctoring

### Web app

The web app handles:

- onboarding
- Mission Control
- findings browser
- proof browser
- ship dashboard
- skills/install/export visibility
- deployment advisor

### MCP and hosted protocols

These expose the agent-facing governed tool contract.

### Generated assets

CK also ships generated host-native assets such as:

## Step 11: autonomy and improvement loop summaries

CK does not treat every session as the same kind of "agent run." It now derives three additional views from the same governed session record:

- **autonomy profile**: whether the session is effectively advise-only, supervised execute, guarded autonomy, or long-running autonomy
- **outcome profile**: whether the work is aimed at task delivery or an explicit KPI / longer-horizon outcome
- **improvement loop**: whether CK has enough evidence from traces, failure clusters, proofs, and benchmark coverage to recommend the next loop-closing move

Those views are derived, not magical. They come from:

- session metadata and execution brief
- risk tier and approval-heavy constraints
- cyber access mode for security work
- current task / proof state
- trace packet and failure-cluster availability
- benchmark suite availability for the current domain

That means CK can say something operationally useful like:

- "this is supervised execute, not long-running autonomy"
- "this mission has an explicit KPI"
- "the next leverage point is turning failure clusters into evals"

without inventing a second workflow engine or pretending it has unrestricted autonomy.

- plugin bundles
- MCP config
- command bundles
- skills
- rules
- workflows
- hooks
- runtime exports

That is how the same control model becomes usable in many host environments without pretending they all behave the same way.

## The simplest exact summary

ControlKeel works by taking agent work through a governed control loop:

1. understand the work boundary
2. compile posture and runtime recommendation
3. bind the work to session/task state
4. expose governed context and tools to the agent
5. validate risky content before execution
6. persist findings and review state
7. capture proof and continuity artifacts
8. evaluate readiness, outcomes, and benchmarks

The reason it feels different from a host is that a host usually helps an agent **do work**.

ControlKeel helps a team **govern work done by agents**.

That difference is the entire product.
