---
name: cloudflare-agent
description: "Enable ControlKeel governance for Cloudflare Agents with policy gates, budget enforcement, PII detection, and secure execution."
license: Apache-2.0
compatibility:
  - cloudflare-workers-runtime
  - open-standard
disable-model-invocation: true
metadata:
  author: controlkeel
  version: "1.0"
  category: integration
---

# Cloudflare Agent Governance

## Overview

This skill enables ControlKeel to govern Cloudflare Agents by providing policy gates, budget enforcement, audit logging, and secure execution capabilities.

## When to Use

Use this skill when:
- Building Cloudflare Agents that need governance guardrails
- Enforcing budget/spend limits on Workers AI or external providers
- Auditing agent actions for compliance
- Running shell commands in sandboxed environments within CF Agents
- Integrating PII detection and security scanning

## Prerequisites

- Cloudflare Workers project with Agents SDK installed
- ControlKeel MCP connected to the agent
- For shell tools: ExecutionSandbox adapter (local/docker/e2b)

## Integration Pattern

### 1. Connect CK to Cloudflare Agent via MCP

The agent exposes governance tools via MCP:

```typescript
import { McpAgent } from "agents/mcp";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

export class GovernedAgent extends McpAgent {
  server = new McpServer({
    name: "controlkeel-governance",
    version: "1.0.0"
  });

  async init() {
    // Register CK governance tools
    this.server.tool(
      "ck_validate",
      "Validate an action against governance policies",
      { prompt: z.string(), context: z.record(z.string(), z.any()).optional() },
      async ({ prompt, context }) => {
        // Call CK governance endpoint
        return await this.callCKGovernance(prompt, context);
      }
    );

    this.server.tool(
      "ck_budget_check",
      "Check remaining budget for AI spend",
      { scope: z.enum(["task", "session", "daily"]).optional() },
      async ({ scope }) => {
        // Query CK budget state
        return await this.callCKBudget(scope || "task");
      }
    );
  }

  async callCKGovernance(prompt: string, context?: Record<string, any>) {
    const response = await this.env.CK_GOVERNANCE.fetch("/validate", {
      method: "POST",
      body: JSON.stringify({ prompt, context })
    });
    return response.json();
  }
}
```

### 2. Policy Gate Pattern

Validate before execution:

```typescript
export class GovernedAgent extends Agent {
  @callable()
  async executeWithGovernance(command: string, args: string[]) {
    // Pre-execution policy check
    const validation = await this.validateWithCK({
      action: "execute_command",
      payload: { command, args }
    });

    if (validation.decision === "denied") {
      return { error: "Policy violation", reason: validation.reason };
    }

    // Execute if approved
    const result = await this.executeCommand(command, args);

    // Post-execution audit
    await this.auditWithCK({
      action: "command_executed",
      payload: { command, args, result },
      validation_id: validation.id
    });

    return result;
  }
}
```

### 3. Budget Enforcement

```typescript
export class BudgetedAgent extends Agent {
  @callable()
  async callAIWithBudget(model: string, messages: any[]) {
    // Check budget before AI call
    const budget = await this.ckBudgetCheck("task");
    
    if (!budget.has_remaining) {
      return { error: "Budget exhausted", remaining: 0 };
    }

    // Make AI call
    const response = await this.callAI(model, messages);

    // Deduct from budget
    await this.ckBudgetDeduct({
      amount: response.usage_tokens,
      scope: "task"
    });

    return response;
  }
}
```

### 4. Shell Execution (via CK ExecutionSandbox)

For agents that need shell access:

```typescript
export class ShellEnabledAgent extends Agent {
  @callable()
  async shell(command: string, cwd?: string) {
    // Validate shell command
    const validation = await this.validateWithCK({
      action: "shell_execution",
      payload: { command, cwd }
    });

    if (validation.decision === "denied") {
      throw new Error(`Shell denied: ${validation.reason}`);
    }

    // Execute via CK sandbox (local/docker/e2b)
    const result = await this.env.CK_SANDBOX.fetch("/execute", {
      method: "POST",
      body: JSON.stringify({
        command,
        cwd: cwd || this.state.cwd || "/workspace",
        sandbox: "local" // or docker, e2b
      })
    });

    return result.json();
  }
}
```

### 5. File System via R2

```typescript
export class FileEnabledAgent extends Agent {
  @callable()
  async readFile(path: string) {
    const object = await this.env.AGENT_BUCKET.get(path);
    if (!object) throw new Error(`File not found: ${path}`);
    return await object.text();
  }

  @callable()
  async writeFile(path: string, content: string) {
    await this.env.AGENT_BUCKET.put(path, content);
    return { success: true, path };
  }

  @callable()
  async listFiles(prefix: string) {
    const objects = await this.env.AGENT_BUCKET.list({ prefix });
    return objects.objects.map(o => o.key);
  }
}
```

### 6. SQLite via D1

```typescript
export class DBEnabledAgent extends Agent {
  @callable()
  async query(sql: string, params?: any[]) {
    const stmt = await this.env.DB.prepare(sql);
    return params ? stmt.bind(...params).all() : stmt.all();
  }

  @callable()
  async initSchema() {
    await this.env.DB.exec(`
      CREATE TABLE IF NOT EXISTS agent_state (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
      );
    `);
  }
}
```

## Tools Reference

### MCP Tools (serve to agents)

| Tool | Description | Parameters |
|------|-------------|------------|
| `ck_validate` | Validate action against policies | `prompt`, `context` |
| `ck_budget_check` | Check remaining budget | `scope` |
| `ck_budget_deduct` | Deduct from budget | `amount`, `scope` |
| `ck_finding` | Log a finding | `severity`, `message`, `payload` |
| `ck_context` | Get governance context | - |
| `ck_delegate` | Delegate to sub-agent | `agent`, `task` |

### CK to Agent Tools

| Tool | Description |
|------|-------------|
| `ck_shell` | Execute shell command (sandboxed) |
| `ck_read` | Read file from agent workspace |
| `ck_write` | Write file to agent workspace |
| `ck_ai` | Call AI with budget tracking |

## Environment Variables

```bash
# CK Governance endpoint (Durable Object or external)
CK_GOVERNANCE=do://agent-governance

# CK Sandbox endpoint
CK_SANDBOX=do://agent-sandbox

# Agent bucket (R2)
AGENT_BUCKET=agent-workspace

# Agent database (D1)
DB=agent-db
```

## Example: Complete Governed Agent

```typescript
import { Agent, callable } from "agents";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

type Env = {
  CK_GOVERNANCE: DurableObjectNamespace;
  AGENT_BUCKET: R2Bucket;
  DB: D1Database;
  AI: Ai;
};

export class GovernedCFAgent extends Agent<Env, { cwd: string }> {
  initialState = { cwd: "/workspace" };

  async onStart() {
    await this.initDB();
  }

  async initDB() {
    await this.env.DB.exec(`
      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY,
        action TEXT,
        payload TEXT,
        timestamp INTEGER
      );
    `);
  }

  @callable()
  async executeCommand(cmd: string, args: string[]) {
    // 1. Validate
    const validation = await this.validateAction("execute", { cmd, args });
    if (validation.denied) {
      await this.log("validation_denied", { cmd, reason: validation.reason });
      return { error: validation.reason };
    }

    // 2. Execute
    const result = await this.runCommand(cmd, args);

    // 3. Audit
    await this.log("executed", { cmd, args, exitCode: result.exitCode });

    return result;
  }

  @callable()
  async readFile(path: string) {
    const fullPath = `${this.state.cwd}/${path}`;
    const obj = await this.env.AGENT_BUCKET.get(fullPath);
    return obj?.text() || null;
  }

  @callable()
  async writeFile(path: string, content: string) {
    const fullPath = `${this.state.cwd}/${path}`;
    await this.env.AGENT_BUCKET.put(fullPath, content);
    await this.log("file_written", { path: fullPath });
    return { success: true };
  }

  private async validateAction(action: string, payload: any) {
    const stub = this.env.CK_GOVERNANCE.get(this.env.CK_GOVERNANCE.idFromName("default"));
    return await stub.validate({ action, payload, context: this.state });
  }

  private async log(action: string, payload: any) {
    await this.env.DB.prepare(
      "INSERT INTO logs (action, payload, timestamp) VALUES (?, ?, ?)"
    ).bind(action, JSON.stringify(payload), Date.now()).run();
  }

  private async runCommand(cmd: string, args: string[]): Promise<{ output: string; exitCode: number }> {
    // Execute via CK sandbox or direct
    const fullCommand = [cmd, ...args].join(" ");
    return { output: `Executed: ${fullCommand}`, exitCode: 0 };
  }
}
```

## Security Considerations

1. **Shell commands** - Always validate via CK policy gates before execution
2. **File access** - Restrict to workspace directory, validate paths
3. **AI budget** - Set per-task and daily limits
4. **Audit logging** - Log all governance decisions and actions
5. **PII scanning** - Use CK PIIDetector on prompts/responses

## Deployment

```bash
# Deploy to Cloudflare Workers
wrangler deploy

# Bind required resources
# - D1 database for agent state
# - R2 bucket for file workspace
# - Durable Object for governance
# - Workers AI or external provider
```
