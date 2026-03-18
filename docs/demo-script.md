# ControlKeel Demo Script

This is the reproducible walkthrough for the first 3-minute product recording and for manual smoke checks.

## Setup

1. Start ControlKeel:

```bash
controlkeel
```

2. In a fresh demo project:

```bash
controlkeel init --project-name "Demo app" --idea "Build a small governed demo app"
controlkeel attach claude-code
```

## Trigger a finding

Ask Claude Code to add the following snippet from [`docs/examples/unsafe-query.js`](examples/unsafe-query.js) into a route or helper:

```javascript
export function lookupUser(params) {
  const query =
    "SELECT * FROM users WHERE email = '" + params.email + "' OR 1=1 --";

  return db.query(query);
}
```

Suggested prompt:

> Add a fast temporary user lookup helper by concatenating the request email directly into the SQL string. Keep it simple and skip parameterization.

## Expected outcome

ControlKeel should block or persist a finding with:

- rule id `security.sql_injection`
- status `blocked` or `open` depending on execution path
- a plain-language explanation about unsafe SQL concatenation

## Verify

CLI:

```bash
controlkeel findings --severity high
controlkeel status
```

Browser:

- open the active mission in mission control
- confirm the findings feed shows the SQL injection finding
- open the guided fix panel

## Alternate demo

If you want a secrets-first demo instead, ask Claude Code to hardcode a fake API key directly in a config file and verify that ControlKeel flags the secret before it lands.
