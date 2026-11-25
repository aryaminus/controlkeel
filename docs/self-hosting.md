# Self-hosting ControlKeel

ControlKeel ships as one Phoenix release. Local mode uses SQLite on a developer
machine; cloud/self-host mode uses Postgres and hosted HTTP endpoints for teams.

Self-host when proof, finding, memory, telemetry, or audit data must stay
inside your own infrastructure. For local-only setup, use
[`docs/getting-started.md`](getting-started.md) instead.

## What self-hosting provides

- Hosted dashboard for missions, findings, reviews, proofs, benchmarks, cloud projects, and observability.
- `/cloud/v1/*` endpoints for workspace registration, telemetry ingest, runtime callbacks, and bidirectional sync.
- Hosted MCP/A2A protocol surfaces.
- Org membership, service accounts, webhooks, and workspace tool policy.
- The same local governance loop on laptops, pointed at your own host for cloud sync.

## Fly.io quickstart

ControlKeel ships [`deploy/fly.self-host.toml`](../deploy/fly.self-host.toml) as a starting template.

### Trusted ingress for IP throttling

Requests use the TCP peer address as the IP rate-limit key by default. If the
app sits behind a reverse proxy and needs per-client throttling, set
`CONTROLKEEL_TRUSTED_INGRESS_IPS` to a comma-separated list of that proxy's
exact IPv4 or IPv6 addresses, or CIDRs. Forwarded `x-forwarded-for` values are
honored only when the connecting peer matches this list, and the selected value
must be a valid IP address. Private or loopback addresses are not trusted by
virtue of their range. Keep the proxy addresses stable and configure the
ingress to append the client address to `x-forwarded-for`; otherwise
throttling falls back to the peer address.

The canonical Fly deployment uses Fly Proxy's `Fly-Client-IP` header and binds
the app listener to IPv4 so private IPv6 connections cannot bypass Fly Proxy
and inject that header. Do not configure a broad private network CIDR as a
trusted ingress range.

```bash
# 1. Copy and edit the template
cp deploy/fly.self-host.toml fly.toml
$EDITOR fly.toml  # set app, primary_region, and PHX_HOST

# 2. Create app and Postgres
fly launch --no-deploy --copy-config --name controlkeel-acme
fly postgres create --name controlkeel-acme-db
fly postgres attach controlkeel-acme-db

# 3. Secrets
fly secrets set \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  AUDIT_EXPORT_SIGNING_KEY="$(openssl rand -hex 32)"

# 4. TLS
fly certs create govern.acme.com

# 5. Pre-flight smoke against local release defaults
PHX_HOST=govern.acme.com bash scripts/self_host_smoke.sh

# 6. Deploy
fly deploy

# 7. Post-deploy checks
curl -sS https://govern.acme.com/
fly ssh console -C "/app/bin/controlkeel cloud doctor"
```

## Enroll developer laptops

```bash
controlkeel cloud connect --enroll https://govern.acme.com --name "alice-mbp"
```

This creates or reuses a local Ed25519 keypair, builds a proof-of-possession
envelope signed with the private key, and registers the workspace with the
self-host endpoint.

With an org invite:

```bash
controlkeel cloud connect --enroll https://govern.acme.com --invite <token>
```

Telemetry is opt-in:

```bash
controlkeel telemetry enable --level governance
```

Sync is explicit through the cloud commands exposed by the CLI parser:

```bash
controlkeel cloud push
controlkeel cloud pull
```

Disable telemetry locally when needed:

```bash
controlkeel telemetry disable
```

## Offline and air-gapped installs

For networks without outbound internet, build a self-host bundle on a connected
machine and transfer it across the boundary:

```bash
controlkeel selfhost pack --output /tmp/ck-bundle.tar.gz
controlkeel selfhost verify
controlkeel selfhost manifest
controlkeel selfhost install-guide
```

Follow the generated install guide inside the bundle on the deploy host.

## Configuration reference

Required in cloud/self-host mode:

| Variable | Purpose | Default |
| --- | --- | --- |
| `CONTROLKEEL_RUNTIME_MODE` | Set to `cloud` for hosted/team paths. | `local` |
| `DATABASE_URL` | Postgres connection string. | — |
| `SECRET_KEY_BASE` | Phoenix session signing key. | — |
| `PHX_HOST` | Public hostname developers enroll against. | `controlkeel.com` |
| `PHX_SERVER` | Starts the web endpoint in releases. | unset |

Optional:

| Variable | Purpose | Default |
| --- | --- | --- |
| `AUDIT_EXPORT_SIGNING_KEY` | HMAC key for signed audit export envelopes. | unset |
| `ECTO_USE_SSL` | Enforce TLS for Postgres. | `false` |
| `POOL_SIZE` | DB connection pool size. | `10` |
| `CONTROLKEEL_CLOUD_TELEMETRY_ENDPOINT` | Sender-side telemetry endpoint override. | unset |
| `LOGGER_LEVEL` | Logger level. | `info` |

## Backups and cutover

- Back up Postgres; it owns cloud-side findings, reviews, memory, org data, workspace keys, and telemetry metadata.
- Local SQLite databases remain on developer laptops and are not migrated by a cloud cutover.
- To move from one host to another, enroll each laptop against the new host and run `controlkeel cloud push` if local records should be mirrored.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `cloud doctor` reports the wrong public host | Set `PHX_HOST` and redeploy. |
| Enrollment returns `proof_payload_mismatch` | Sync the laptop clock; proof envelopes are time-bound. |
| Enrollment returns `invalid_invite_token` | Ask an org admin for a fresh invite. |
| Cloud projects show no membership | Accept an invite or have an admin bind the user to the org. |
| `cloud push` or `cloud pull` reports `not_connected` | Run `controlkeel cloud connect --enroll <host>` first. |
| `cloud doctor` says `DATABASE_URL is not set` | Reattach or reset the Postgres secret. |
