---
name: agent-pattern-verification
description: "Verify AI agent code for dangerous patterns including infinite loops, unbounded retries, tool hallucinations, and context overflow. Use before deploying agent workflows or when reviewing agent code."
when_to_use: "Activate when reviewing agent code, before deploying LangGraph/CrewAI/AutoGen workflows, or when the user asks about agent safety, loops, retries, or tool consistency."
argument-hint: "[agent directory or files to verify]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
  - cline-native
  - cursor-native
  - windsurf-native
  - continue-native
  - letta-code-native
  - pi-native
  - roo-native
  - goose-native
  - opencode-native
  - antigravity-cli-native
  - kiro-native
  - kilo-native
  - amp-native
  - augment-native
  - devin-terminal-native
  - warp-native
  - droid-bundle
metadata:
  author: controlkeel
  version: "1.0"
  category: security
  ck_mcp_tools:
    - ck_context
    - ck_validate
    - ck_finding
---

# Agent Pattern Verification Skill

Verify AI agent code for common anti-patterns that can cause infinite loops, runaway retries, tool mismatches, and context overflow. This skill complements ControlKeel's security and compliance validation with agent-specific pattern detection.

## When to Use

Trigger this skill when:
- Reviewing agent code before deployment
- Validating LangGraph, CrewAI, AutoGen, or LangChain workflows
- User asks about "agent safety", "infinite loops", "retry limits", or "tool consistency"
- Before merging agent workflow changes

## Verification Flow

1. **Call `ck_context`** to load the session context, risk tier, and existing findings
2. **Detect agent framework** by scanning imports and configuration files
3. **Run pattern checks** using the checklist below
4. **Persist findings** with `ck_finding` for each issue discovered
5. **Generate structured report** with pattern-matched vs heuristic tagging

## Pattern Checks

All checks are classified as:
- `[PATTERN]` - Mechanical check, high reliability (applied exactly as specified)
- `[HEURISTIC]` - Judgment-based, best-effort (requires interpretation)

### 1. Loop Safety `[PATTERN]`

Apply mechanically. Do not pass a loop because it "looks like it might terminate."

| Pattern to find | Pass condition | Severity |
|-----------------|----------------|----------|
| `while True:` in Python | A `break` statement exists within the same block scope | ⚠️ Warning if absent |
| `for { }` in Go | A `break` or `return` exists within the block | ⚠️ Warning if absent |
| `while (true)` in TypeScript/JavaScript | A `break` or `return` exists within the block | ⚠️ Warning if absent |
| Recursive function calls | A non-recursive return path exists (base case), OR a depth/counter parameter is present | ⚠️ Warning if absent |

**Heuristic Fallback**: After applying pattern table, scan for:
- Loops where termination depends entirely on external/runtime state with no timeout
- Generator functions that `yield` indefinitely without documented exit
- Event/polling loops without timeout parameters
- Recursive call chains across multiple functions without depth tracking

Flag as ⚠️ Warning: *"Potential unbounded loop not matching known patterns — verify termination condition manually"*

### 2. Retry Limit Enforcement `[PATTERN]`

Apply mechanically. If required parameter is absent, flag as ❌ Issue.

**Python — Decorator-based:**

| Library/Pattern | Required parameter | Fail condition |
|-----------------|-------------------|----------------|
| `@retry` (tenacity) | `stop=stop_after_attempt(n)` or `stop=stop_after_delay(n)` | `stop=` absent |
| `@backoff.on_exception` | `max_tries=n` | `max_tries=` absent |

**Python — HTTP client retry:**

| Library/Pattern | Required parameter | Fail condition |
|-----------------|-------------------|----------------|
| `urllib3.Retry(...)` | `total=n` where n > 0 | `total=` absent or `total=0` |
| `HTTPAdapter(max_retries=Retry(...))` | Retry object must have `total=n` | `total=` absent |
| `httpx.HTTPTransport(retries=n)` | `retries=n` where n > 0 | `retries=` absent or `retries=0` |

**Python — AWS SDK (boto3):**

| Library/Pattern | Required parameter | Fail condition |
|-----------------|-------------------|----------------|
| `Config(retries={...})` | `max_attempts` > 1 | `max_attempts` absent or ≤ 1 |

> Note: boto3 without explicit retry config uses SDK defaults (3 attempts) — do not flag absence.

**JavaScript/TypeScript:**

| Library/Pattern | Required parameter | Fail condition |
|-----------------|-------------------|----------------|
| `retry(...)` (async-retry) | `retries: n` in options | `retries:` absent |
| `pRetry(...)` (p-retry) | `retries: n` in options | `retries:` absent |

**Custom retry loops (all languages):**

| Pattern to find | Pass condition | Fail condition |
|-----------------|----------------|----------------|
| Loop + `try/except` + `continue` | Integer counter with max check | No counter → ❌ Issue |

**Heuristic Fallback**: Scan for:
- Functions/decorators with "retry" in name not in tables above
- Imported modules with "retry" in package name (e.g. `stamina`, `aiohttp_retry`)
- Loops with sleep + exception handling + re-invocation without visible counter
- Config keys like `max_retries`, `retry_count`, `attempts`

Flag as ⚠️ Warning: *"Potential retry pattern not matching known libraries — verify retry bounds manually"*

### 3. Tool Registry Consistency `[PATTERN]`

**Step 1: Collect defined tools**

Scan tool definition files. A name found by any pattern counts as registered.

*Python — decorator patterns:*

| Pattern | How to extract name |
|---------|---------------------|
| `@tool` (LangChain) on `def` | Function name below decorator |
| `@function_tool` (OpenAI Agents SDK) on `def` | Function name below decorator |
| `@tool(name="...")` | Use `name=` argument value |

*Python — dict/list patterns:*

| Pattern | How to extract name |
|---------|---------------------|
| `{"type": "function", "function": {"name": "..."}}` (OpenAI) | Value of `"name"` inside `"function"` |
| `{"name": "...", "input_schema": {...}}` (Anthropic) | Top-level `"name"` |
| `{"name": "...", "description": "...", "parameters": {...}}` | Top-level `"name"` |
| `ToolNode([func1, func2, ...])` (LangGraph) | Each function name in list |
| `tools = [func1, func2]` / `TOOLS = [...]` | Each identifier in list |

*TypeScript/JavaScript:*

| Pattern | How to extract name |
|---------|---------------------|
| `{ type: "function", function: { name: "..." } }` (OpenAI) | `name:` inside `function:` |
| `tool({ description: "...", parameters: z.object({...}) })` | The `const` variable name |
| `new DynamicTool({ name: "...", ... })` (LangChain.js) | Value of `name:` |
| `zodFunction({ name: "...", ... })` | Value of `name:` |

**Step 2: Collect tool references from prompts**

Scan `.md`, `.txt`, `prompts.py` for backtick-quoted identifiers naming capabilities.

**Step 3: Cross-reference**

| Finding | Severity |
|---------|----------|
| Reference not in definition list | ❌ Issue (hallucinated tool) |
| Defined tool not in any prompt | ⚠️ Warning (undocumented tool) |

**Heuristic**: Find where tools are defined and where LLM is invoked. If tools exist but are never connected to the LLM call, flag as ❌ Issue: *"Tools defined but never connected to LLM invocation"*

**Heuristic Fallback**: Scan for tool-like structures:
- Dicts with both `"description"` and `"parameters"` keys
- Functions with structured docstrings (name, params, return)
- Variables named `tools`, `tool_list`, `available_tools`, `functions`
- Classes with `run()`, `execute()`, or `__call__()` methods

Include in count and note: *"Tool detected via heuristic — verify this is an intended agent tool."*

### 4. Context Size Awareness `[PATTERN]`

Formula: `token_estimate = len(file_content_chars) / 4`

| Content | ⚠️ Warning threshold | ❌ Issue threshold |
|---------|----------------------|-------------------|
| System prompt file | > 4,000 tokens | > 8,000 tokens |
| Single tool description | > 500 tokens | > 1,000 tokens |
| All tool descriptions combined | > 2,000 tokens | > 4,000 tokens |

**Exclude**: `skills/` directories (loaded on demand, not embedded)

**Heuristic Fallback**:
- Estimates within 20% of threshold → flag with tokenizer recommendation
- Dynamic prompts (f-strings, `.format()`) → flag if template alone is large
- Multiple concatenated prompts → estimate combined size
- Prompts with includes → note effective size may be larger

### 5. LangGraph Graph Cycle Analysis `[PATTERN]`

*(Only when LangGraph is detected)*

**Detection steps:**
a. Find graph file (`graph.py`, `graph.ts`, or file with `StateGraph`/`MessageGraph`)
b. Build edge map:
   - `workflow.add_edge(source, dest)` — unconditional edge
   - `workflow.add_conditional_edges(source, fn, mapping)` — extract destinations from mapping
c. Identify cycles: nodes reachable from themselves
d. For each cycle, check if `END` (or `"__end__"`) is reachable via conditional edge

| Condition | Severity |
|-----------|----------|
| Cycle exists, `END` reachable via conditional | ✅ Pass |
| Cycle exists, no path to `END` | ❌ Issue |
| Graph has no `END` node | ❌ Issue |
| Node has no outgoing edges and is not `END` | ⚠️ Warning (dead-end) |

## Framework Detection

Identify the agent framework by checking imports:

| Import Pattern | Framework |
|----------------|-----------|
| `from langgraph` or `import langgraph` | LangGraph |
| `from crewai` or `import crewai` | CrewAI |
| `from autogen` or `import autogen` | AutoGen |
| `from langchain` or `import langchain` | LangChain |
| Direct `openai`/`anthropic` SDK only | Custom |

Also check for framework config files: `langgraph.json`, `crew.yaml`.

## File Discovery

**Priority files:**
- `graph.py`, `graph.ts` - Agent workflow definitions
- `tools.py`, `tools.ts`, `tools/*.py`, `tools/*.ts` - Tool implementations
- `state.py`, `state.ts` - State schemas
- `prompts.py`, `prompts/*.md`, `system.md` - Prompt templates
- `agent.py`, `agent.ts` - Main agent logic

**Directories to check:**
- `src/agent/`, `agent/`, `src/`, project root
- `lib/`, `app/`, `packages/`

**Exclude from analysis:**
- `skills/` directory — these are skill definitions, not agent system prompts

## Report Format

Generate a structured report with the following format:

```markdown
# Agent Pattern Verification Report

**Project:** [project name or path]
**Date:** [current date]
**Framework:** [LangGraph | CrewAI | AutoGen | LangChain | Custom | None]
**Files analyzed:** [count]

## Summary

✅ X checks passed | ⚠️ Y warnings | ❌ Z issues

### By Category

| Category | Pass | Warn | Issue |
|----------|------|------|-------|
| Loop Safety | X | X | X |
| Retry Limits | X | X | X |
| Tool Consistency | X | X | X |
| Context Size | X | X | X |
| Graph Cycles | X | X | X |

## Detailed Findings

> `[P]` = pattern-matched (structurally reliable) · `[H]` = heuristic (best-effort judgment)

### ✅ Passing

- `[P]` All retry decorators have stop conditions
- `[P]` Tool registry consistent with prompt references

### ⚠️ Warnings

- `[P|H]` [Check name]: [Description]
  - **Location:** [file:line]
  - **Category:** [Loop Safety | Retry Limits | Tool Consistency | Context Size]
  - **Suggestion:** [How to address]

### ❌ Issues

- `[P|H]` [Check name]: [Description]
  - **Location:** [file:line]
  - **Category:** [Loop Safety | Retry Limits | Tool Consistency | Context Size]
  - **Rule:** [Which rule this violates]
  - **Fix:** [Specific remediation steps]

## Recommendations

1. **[Highest priority]** - [Specific action]
2. **[Second priority]** - [Specific action]
3. [Additional improvements]

---

*Report generated by ControlKeel Agent Pattern Verification v1.0*
```

## Integration with CK Tools

### Using `ck_validate`

For pattern-matched checks that can be expressed as code patterns, use `ck_validate` with:
- `artifact_type: "source"`
- `intended_use: "code"`
- `domain_pack: "software"` or relevant domain
- `security_workflow_phase: "analysis"`

### Using `ck_finding`

Persist each issue with structured metadata:
```elixir
ck_finding(
  category: "security",
  finding_family: "agent_pattern",
  affected_component: "agent/loop.py:45",
  severity: "warning",  # or "issue"
  evidence_type: "code_pattern",
  description: "Potential unbounded loop detected",
  suggested_fix: "Add MAX_ITERATIONS constant or break condition",
  check_type: "pattern"  # or "heuristic"
)
```

### Using `ck_context`

Call at the start to:
- Load existing findings to avoid duplicates
- Understand the risk tier and compliance profile
- Get workspace context for file discovery

## Additional Resources

For detailed check specifications and examples, see [references/pattern-checklist.md](references/pattern-checklist.md).