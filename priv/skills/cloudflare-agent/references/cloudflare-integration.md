# Cloudflare Agent Governance Configuration

## Quick Start

### 1. Create Cloudflare Worker with Agents SDK

```bash
npx create-cloudflare@latest --template cloudflare/agents-starter my-governed-agent
cd my-governed-agent
npm install
```

### 2. Add CK Governance Tools

Create `src/governance.ts`:

```typescript
import type { Env } from "./env";

export async function validateWithCK(env: Env, action: string, payload: any) {
  const response = await env.CK_GOVERNANCE.fetch("https://your-ck-instance/validate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      action,
      payload,
      agent: "cloudflare-agent",
      version: "1.0.0"
    })
  });
  return response.json();
}

export async function checkBudget(env: Env, scope: string = "task") {
  const response = await env.CK_GOVERNANCE.fetch(`https://your-ck-instance/budget/${scope}`);
  return response.json();
}
```

### 3. Configure wrangler.toml

```toml
name = "governed-agent"
main = "src/index.ts"
compatibility_date = "2025-03-02"

[[d1_databases]]
binding = "DB"
database_name = "agent-db"
database_id = "your-d1-id"

[[r2_buckets]]
binding = "AGENT_BUCKET"
bucket_name = "agent-workspace"

[[unsafe.bindings]]
name = "CK_GOVERNANCE"
type = "durable_object_namespace"
class_name = "GovernanceDO"

[env.production.vars]
CK_INSTANCE = "https://controlkeel.yourdomain.com"
```

### 4. Create D1 Database

```bash
wrangler d1 create agent-db
wrangler d1 execute agent-db --local --command="
  CREATE TABLE IF NOT EXISTS agent_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    action TEXT NOT NULL,
    payload TEXT,
    decision TEXT,
    budget_before INTEGER,
    budget_after INTEGER
  );
  
  CREATE TABLE IF NOT EXISTS agent_state (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at INTEGER
  );
"
```

## R2 Bucket Setup

```bash
# Create R2 bucket for agent workspace
wrangler r2 bucket create agent-workspace
```

## Governance Rules Example

Configure in CK:

```json
{
  "policy": {
    "shell": {
      "allowed_commands": ["git", "npm", "node", "python", "cargo"],
      "blocked_patterns": ["rm -rf /", "sudo", "chmod 777"],
      "max_duration_ms": 60000
    },
    "file_access": {
      "allowed_paths": ["/workspace/*"],
      "max_file_size_mb": 10
    },
    "budget": {
      "task": { "max_tokens": 100000, "max_calls": 50 },
      "daily": { "max_tokens": 1000000, "max_calls": 500 }
    }
  }
}
```

## MCP Server Setup

```typescript
// src/mcp/governance.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function createGovernanceMCP(env: Env) {
  const server = new McpServer({
    name: "controlkeel-governance",
    version: "1.0.0"
  });

  server.tool(
    "ck_validate",
    "Validate an action against governance policies",
    {
      action: z.string(),
      payload: z.record(z.any())
    },
    async ({ action, payload }) => {
      return await validateWithCK(env, action, payload);
    }
  );

  server.tool(
    "ck_budget_check",
    "Check remaining budget",
    {
      scope: z.enum(["task", "session", "daily"]).optional()
    },
    async ({ scope }) => {
      return await checkBudget(env, scope || "task");
    }
  );

  return server;
}
```

## Testing Governance

```typescript
// test/governance.test.ts
import { describe, it, expect } from "vitest";

describe("Cloudflare Agent Governance", () => {
  it("should validate shell commands", async () => {
    const result = await validateWithCK(env, "shell_execute", {
      command: "npm install"
    });
    expect(result.decision).toBe("approved");
  });

  it("should block dangerous commands", async () => {
    const result = await validateWithCK(env, "shell_execute", {
      command: "rm -rf /"
    });
    expect(result.decision).toBe("denied");
  });

  it("should track budget", async () => {
    const before = await checkBudget(env, "task");
    // make API call...
    const after = await checkBudget(env, "task");
    expect(after.remaining).toBeLessThan(before.remaining);
  });
});
```

## Monitoring

### Log Queries

```sql
-- Recent governance decisions
SELECT * FROM agent_logs 
ORDER BY timestamp DESC 
LIMIT 20;

-- Blocked actions
SELECT * FROM agent_logs 
WHERE decision = 'denied' 
ORDER BY timestamp DESC;

-- Budget usage
SELECT 
  DATE(timestamp, 'unixepoch') as day,
  COUNT(*) as total_actions,
  SUM(json_extract(payload, '$.tokens')) as tokens_used
FROM agent_logs
GROUP BY day;
```

### Prometheus Metrics

Configure in `wrangler.toml`:

```toml
[observability]
enabled = true
```

Track:
- `governance_decisions_total{decision="approved|denied"}`
- `budget_consumed_tokens`
- `shell_execution_duration_ms`
- `file_operations_total`
