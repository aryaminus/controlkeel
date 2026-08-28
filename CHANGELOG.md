# Changelog

## v0.4.3 — 2026-08-28

### What's changed

- Merge pull request #134 from aryaminus/fix/p2-god-module-splits
- Merge pull request #133 from aryaminus/fix/p2-streamable-http-mcp
- Merge pull request #132 from aryaminus/fix/p2-llm-judge-harness
- refactor: first god-module split — Mission.FindingOps + API.FindingController
- feat(mcp): Streamable HTTP session semantics (Mcp-Session-Id lifecycle)
- feat(benchmark): LLM-as-judge harness for eval_mode=llm_judge
- Merge pull request #128 from aryaminus/fix/dogfood-mcp-cli-review-loop
- fix(surface): token-surface deprecation, honest skills doctor signal, alias deprecated skills
- fix(housekeeping): honest skills doctor signal, installer self-heal, token audit join
- style: mix format
- fix(audit): full P0+P1 remediation across governance, storage, policy, eval, CLI
- feat: smart auto-approval for low-risk work
- fix: inline-first approval flow across all clients
- fix: actionable duplicate skill cleanup guidance + --prune-duplicates flag
- fix: MCP/CLI review loop, ck_fs_find glob support, updater orphan cleanup

## v0.4.2 — 2026-08-27

### What's changed

- Merge pull request #120 from aryaminus/refactor/web-policy-studio
- Merge pull request #114 from aryaminus/refactor/web-deploy
- Merge pull request #112 from aryaminus/refactor/web-benchmark
- refactor/web-policy-studio: implement web-based policy management and rename tool-policy tab to agent-tools
- refactor/web-policy-studio: add reusable modal component and refactor policy studio dialogs to use it
- refactor/web-policy-studio: remove form binding from tool policy UI and introduce reusable rule_tag component
- refactor/web-policy-studio: remove workspace role enforcement temporarily to permit viewer access pending centralized auth transition
- refactor/web-policy-studio: add ability to toggle policy set assignment status and exclude disabled assignments from evaluation
- refactor/web-policy-studio: validate policy precedence range and display detailed changeset errors in workspace settings
- refactor/web-policy-studio: rename tool policy UI to agent tools and add breadcrumbs to workspace views
- refactor/web-policy-studio: add support for breadcrumbs in dashboard layout
- refactor/web-policy-studio: implement workspace-level policy
- refactor/web-policy-studio: update policy studio layout
- refactor/web-policy-studio: refine Policy Studio UI for better usability
- refactor/web-policy-studio: update core components with error rendering, and simplify Policy Studio layout
- refactor/web-policy-studio: add Policy Studio UI for creating policy sets
- refactor/web-policy-studio: update Policy Studio to list global policy sets.
- refactor/web-deploy: standardize deployment UI components
- refactor/web-deploy: implement file write error handling in DeploymentAdvisor and add comprehensive LiveView test suite for deploy review.
- refactor/web-deploy: replace global deployment page with session-scoped DeployReviewLive and move deployment advisor functionality to the session context.
- refactor/web-deploy: add file copy event to mission control
- refactor/web-deploy: improve deployment modal UI layout
- refactor/web-deploy: migrate deployment UI from global route to session modal.
- refactor/web-deploy: relocate deployment analysis to mission control session modal for improved path resolution
- refactor/web-deploy: remove deployment advisor module and associated UI navigation components

## v0.4.1 — 2026-08-21

### What's changed

- Merge pull request #109 from aryaminus/feat/is-agentic-score-improvement
- Merge remote-tracking branch 'origin/main' into feat/is-agentic-score-improvement
- fix: version bump 0.4.0 + address Greptile review findings
- improve is-agentic score: add OpenAPI, llms.txt, sitemap, 404s, JSON errors, markdown negotiation, trust pages

## v0.4.0 — 2026-08-21

### What's changed

- feat/is-agentic-score-improvement: add OpenAPI 3.1 spec, llms.txt, sitemap.xml, structured JSON errors, markdown content negotiation, JSON-LD schema, trust pages, developer portal, and robots.txt
- Bump version to 0.4.0 across all manifests (mix.exs, npm, plugins, OpenAPI spec, dist manifests)
- fix: address Greptile review findings (markdown negotiation ordering, vendor JSON detection, OpenAPI auth docs, dynamic canonical URLs, typography components)

## v0.3.94 — 2026-08-21

### What's changed

- perf: optimize intermediate list allocations in observability aggregates
- fix: breadcrumb accessibility and focus states
- fix: add ARIA attributes and focus styles to user menu
- fix: add accessibility to findings modal close button

## v0.3.93 — 2026-08-19

### What's changed

- Merge pull request #101 from aryaminus/fix/lint-and-warnings
- fix/lint-and-warnings: remove redundant workspace access checks for nil org_ids
- fix/lint-and-warnings: fix indentation and formatting across LiveViews and utility modules

## v0.3.92 — 2026-08-19

### What's changed

- Merge pull request #100 from aryaminus/refactor/findings-web
- Merge pull request #94 from aryaminus/refactor/observability-web
- refactor/findings-web: remove bulk action functionality and simplify findings browser UI and state management
- refactor/findings-web: implement web UI parity for findings including bulk actions, security summaries, audit trails, and read-only metadata fields
- refactor/findings-web: plan, track, and initiate findings browser parity updates for web and cloud consistency
- refactor/findings-web: implement bulk findings disposition, escalation support, and metadata-based filtering in the Findings web interface.
- refactor/observability-web: add observability loop diagnostics and performance snapshot capture to dashboard
- refactor/observability-web: implement observability cost optimization suggestions and agent cost comparisons on the costs live view
- refactor/observability-web: add auto-hiding flash notifications and enhance status feedback for observability drafts and eval saves.
- refactor/observability-web: add benchmark draft archival and generation features to observability dashboard
- refactor/observability-web: add implementation plans for observability web partitioning and feature promotion.

## v0.3.91 — 2026-08-16

### What's changed

- Merge pull request #87 from aryaminus/refactor/observability-layout
- Merge pull request #84 from aryaminus/refactor/session-review-web
- refactor/observability-layout: update recent sessions component test with detailed finding and budget metrics
- refactor/observability-layout: reduce vertical spacing in observability live view pages
- refactor/observability-layout: overhaul observability UI components with consistent card-based design and updated color tokens
- refactor/observability-layout: remove observability layout and consolidate routes under the dashboard layout
- refactor/observability-layout: implement persistent, scroll-aware, and collapsible sidebar navigation with LiveView hook
- refactor/session-review-web: add revisions card to ReviewLive and update local database configuration
- refactor/session-review-web: nest review routes under sessions and centralize URL generation in ReviewBridge
- refactor/session-review-web: prevent potential crash in ReviewLive when responding to nil review and allow configurable database path in dev config
- refactor/session-review-web: nest review routes under sessions and centralize URL generation in ReviewBridge
- refactor/session-review-web: improve review UI responsiveness, add clipboard support, and configure dev database path
- refactor/session-review-web: standardize form components and add reusable button component with variants
- refactor/session-review-web: redesign ReviewLive UI using standardized components and remove unused review_url state
- refactor/session-review-web: implement session-scoped review URLs and add a SessionReviewsLive view for managing review queues
- refactor/session-review-web: nest review routes under sessions and implement centralized browser URL generation

## v0.3.90 — 2026-08-15

### What's changed

- Merge pull request #80 from aryaminus/a11y/flash-dismiss-focus-ring
- a11y(web): add focus-visible ring to flash dismiss button

## v0.3.89 — 2026-08-12

### What's changed

- Merge pull request #68 from aryaminus/palette/add-command-pill-accessibility-15805215596890986666
- 🎨 Palette: Add accessible labels and focus styles to command pill
- chore: drop bot metadata (.Jules/palette.md) from this branch
- 🎨 Palette: Add accessible labels and focus styles to command pill

## v0.3.88 — 2026-08-12

### What's changed

- Merge pull request #56 from aryaminus/refactor/org-workspace-relation
- refactor/org-workspace-relation: resolve orphan cleanup decision via pre-transaction read to avoid blocking locks during prompt input
- Merge pull request #63 from aryaminus/refactor/cloud-org-workspace-relation
- Merge branch 'refactor/org-workspace-relation' into refactor/cloud-org-workspace-relation
- Merge pull request #66 from aryaminus/refactor/web-mission-to-session
- refactor/org-workspace-relation: update local migration to support optional orphan cleanup and non-destructive reconciliation
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/org-workspace-relation
- refactor/web-mission-to-session: rename mission to session across web UI, routes, and documentation (Part 1)
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/cloud-org-workspace-relation
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/org-workspace-relation
- refactor/cloud-org-workspace-relation: relocate workspace helper functions and remove redundant error handling clauses
- refactor/cloud-org-workspace-relation: update organization CLI and LiveView tests to reflect default workspace settings and role badge rendering changes
- refactor/org-workspace-relation: remove extra newline in local migration documentation
- refactor/cloud-org-workspace-relation: add comment for Cloud project logic.
- refactor/cloud-org-workspace-relation: integrate organization and workspace selection into the cloud mode onboarding flow
- refactor/cloud-org-workspace-relation: implement cloud-mode organization and workspace selection for CLI initialization and web onboarding.
- refactor/cloud-org-workspace-relation: add workspace creation command and CLI infrastructure for cloud-mode organization selection
- refactor/cloud-org-workspace-relation: implement cloud mode for project initialization with support for organization and workspace targeting
- refactor/org-workspace-relation: refactor migration documentation
- refactor/org-workspace-relation: update local migration to repurpose oldest existing orgs and workspaces instead of creating new ones
- refactor/org-workspace-relation: add duplicate project name validation to onboarding wizard
- refactor/org-workspace-relation: enforce Session-Workspace-Org hierarchy by creating default entities and recording org_id in project bindings
- refactor/org-workspace-relation: standardize session creation to use default workspace and remove duplicate project name validation
- refactor/org-workspace-relation: add workspace detail page and link to it from organization view
- refactor/org-workspace-relation: implement workspace management and organization dashboard tabs

## v0.3.87 — 2026-08-09

### What's changed

- Merge pull request #59 from aryaminus/fix/warnings
- Merge branch 'main' of github.com:aryaminus/controlkeel into fix/warnings
- fix/warnings: remove redundant nil checks and simplify session metadata handling across core logic
- fix/warnings: simplify code paths by removing redundant checks and update websockex dependency to 0.5.1

## v0.3.86 — 2026-08-07

### What's changed

- Merge pull request #65 from aryaminus/fix/websockex-deps-lock-mismatch
- chore: upgrade websockex dependency to version 0.5.1

## v0.3.85 — 2026-08-02

### What's changed

- Merge pull request #53 from aryaminus/refactor/page-style
- refactor/page-style: derive can_manage permission and use it to determine organization page actions
- refactor/page-style: update dashboard_header page_action attribute to accept a list of maps
- refactor/page-style: update card_title font size and fix documentation typos
- refactor/page-style: support multiple page actions in dashboard header and standardize organization detail UI components
- refactor/page-style: replace standard anchor tags with Phoenix components for client-side navigation in missions and organizations views
- refactor/page-style: add page_action support to dashboard_header component documentation examples
- refactor/page-style: remove assertion for "New Mission" from dashboard live view test
- refactor/page-style: standardize UI components and modernize design system tokens across dashboards and mission views.
- refactor/page-style: remove provider status components and add typography component and layout defaults module
- refactor/page-style: add UI style guide and introduce Typography component for standardized heading rendering.

## v0.3.84 — 2026-08-01

### What's changed

- Merge pull request #51 from aryaminus/fix/evalcandidate-optimistic-lock
- fix(observability): make optimistic-lock exhaustion warning reachable
- fix(observability): log warning on lifecycle retry exhaustion + correct doc
- fix(observability): optimistic-lock EvalCandidate lifecycle writes (#50)

## v0.3.83 — 2026-07-30

### What's changed

- Merge pull request #52 from aryaminus/refactor/layout-and-style
- refactor/layout-and-style: update Tailwind @apply guidelines and disable non-functional settings button in navigation layout
- refactor/layout-and-style: update observability layouts to use a flexbox shell with a dashboard header and scrollable content area
- refactor/layout-and-style: migrate sidebar and header layout to persistent dashboard structure with added status color variables
- refactor/layout-and-style: dynamic sidebar navigation with active path highlighting
- refactor/layout-and-style: standardize UI components and Tailwind classes by migrating to theme-based semantic colors
- refactor/layout-and-style: remove redundant border color classes from UI components across the codebase
- refactor/layout-and-style: migrate tailwind utility classes from raw CSS variables to semantic theme aliases
- refactor/layout-and-style: migrate UI to standard CSS variables for theme consistency across all live views and components
- refactor/layout-and-style: replace custom component classes with inline Tailwind utility classes across LiveView templates
- refactor/layout-and-style: simplify UI theme by replacing complex radial gradients with static variables and colors

## v0.3.82 — 2026-07-30

### What's changed

- Merge pull request #49 from aryaminus/feat/user-menu
- feat/user-menu: encapsulate user menu into reusable component and update layout logic
- feat/user-menu: replace breadcrumb with dashboard_header and move external links to header
- feat/user-menu: remove OrganizationSettingsLive as functionality is consolidated elsewhere
- feat/user-menu: simplify breadcrumb_trail logic using Enum.with_index and Enum.take
- fix(organizations): align role badge test with reformatted template
- feat/user-menu: implement dynamic breadcrumb component and integrate into dashboard layout via NavHighlight hook
- feat/user-menu: replace simple logout link with user profile menu popover in sidebar

## v0.3.81 — 2026-07-28

### What's changed

- Merge pull request #46 from aryaminus/fix/cloud-mode-postgres-routing
- fix(cloud): parse self_hosted in runtime.exs via Mode.parse (P1)
- fix(cloud): gate repo supervision/migration on real config, not bare env
- Merge remote-tracking branch 'origin/main' into fix/cloud-mode-postgres-routing
- fix(cloud): route cloud-mode queries to Postgres via a runtime dispatcher

## v0.3.80 — 2026-07-28

### What's changed

- Merge pull request #47 from aryaminus/refactor/odic-saml
- refactor/odic-saml: ensure is_owner assignment evaluates to a strict boolean
- fix(org-settings): re-check can_manage before saving org settings
- refactor/odic-saml: remove redundant settings_saved state and update documentation terminology
- refactor/odic-saml: remove organization settings page and decommission SSO/IdP support logic
- refactor/org-membership: begin removal of SSO, OIDC, and SAML support across documentation, configuration, and settings UI
- refactor/org-membership: remove OIDC and SAML SSO support and associated tests
- refactor/org-membership: remove all SSO, OIDC, and SAML identity provider functionality and CLI commands
- refactor/org-membership: remove SSO, OIDC, and SAML identity provider functionality from organization settings
- refactor/org-membership: remove all OIDC and SAML identity provider functionality and database configuration
- refactor/org-membership: remove SSO, OIDC, and SAML authentication modules and associated routes, controllers, and UI components

## v0.3.79 — 2026-07-28

### What's changed

- Merge pull request #45 from aryaminus/refactor/org-membership
- Merge remote-tracking branch 'origin/main' into refactor/org-membership
- refactor/org-membership: add membership existence check to prevent errors when opening revocation modal
- refactor/org-membership: update page title in InvitationLive mount
- refactor/org-membership: update invitation routes, enforce membership checks in controller tests, and adjust environment configurations
- refactor/org-membership: add revoked_at timestamp to memberships and update revocation logic
- refactor/org-membership: add configurable status filtering to list_memberships_for_org and hide revoked memberships by default
- refactor/org-membership: implement role-based authorization for organization invitations and restrict invite UI options by role
- refactor/org-membership: implement role-based access control for organization membership invitations and role updates
- refactor/org-membership: implement role-based authorization for organization membership revocation
- refactor/org-membership: simplify invitation routes by removing /cloud prefix and restrict access in local mode
- refactor/org-membership: replace completion token auth flow with session-based pending invitation persistence
- refactor/org-membership: invitation layout and routes
- refactor/org-membership: enable re-invitation of previously revoked members by reviving memberships instead of failing

## v0.3.78 — 2026-07-27

### What's changed

- Merge pull request #43 from aryaminus/feat/deterministic-promotion
- fix(observability): eliminate same-second lifecycle ties via monotonic seq
- fix(observability): resolve same-second lifecycle timestamp tie in promotion
- fix(observability): preserve approval and use latest lifecycle marker in promotion
- fix(organizations): align role badge test with reformatted template
- feat(observability): deterministic promotion path for recurring agent behavior

## v0.3.77 — 2026-07-23

### What's changed

- Merge pull request #39 from aryaminus/refactor/organization-enroll
- refactor/organization-enroll: fix organization membership invitation logic in integration tests
- refactor/organization-enroll: compress organization role span element to single line
- refactor/organization-enroll: rename OrgSettingsLive to OrganizationSettingsLive for route consistency
- refactor/organization-enroll: add OAuth configuration to env example and introduce docker-cloud-compose for cloud runtime support
- refactor/organization-enroll: add organization detail summary dashboard with budget and member count stats
- refactor/organization-enroll: implement invite member modal and redesign organization membership view with local mode support
- refactor/organization-enroll: consolidate organization settings into a single LiveView and rename organization routes
- refactor/organization-enroll: implement per-URL membership validation in organization live views to replace session-pinned checks
- refactor/organization-enroll: implement organization management with support for local and cloud runtime modes

## v0.3.76 — 2026-07-23

### What's changed

- Internal maintenance release.

## v0.3.75 — 2026-07-23

### What's changed

- Merge pull request #42 from aryaminus/fix/git-commit-finding-count
- Merge remote-tracking branch 'origin/main' into fix/git-commit-finding-count
- fix(cli): redact proxy credentials from status
- fix(governance): harden commit-gate findings output
- fix(governance): inspect governed DB + dormancy for stale findings
- fix(git): surface blocking findings in commit gate

## v0.3.74 — 2026-07-23

### What's changed

- Merge pull request #41 from aryaminus/feat/autonomy-scheduler
- docs(autonomy): forbid daemonizing launchers
- fix(autonomy): confirm timeout process-tree shutdown
- fix(autonomy): delimit negative process group IDs
- test(autonomy): treat reaping zombies as terminated
- fix(autonomy): preserve Unix launcher process identity
- fix(autonomy): prevent overlap and terminate launch trees
- test(autonomy): scope SQLite fault injection to SQLite
- fix(autonomy): enforce atomic audited bounded dispatch
- feat(autonomy): governed scheduler + capability-gated shell launcher

## v0.3.73 — 2026-07-22

### What's changed

- Merge pull request #38 from aryaminus/feat/web-oauth
- Merge branch 'main' of github.com:aryaminus/controlkeel into feat/web-oauth
- feat/web-oauth: mock runtime_mode as cloud in AuthController tests
- feat/web-oauth: set and restore runtime_mode to :cloud in OIDC and SAML controller tests
- feat/web-oauth: correct GitHub strategy module name in documentation
- feat/web-oauth: add formatted OAuth provider names and comprehensive controller and plug tests
- feat/web-oauth: sanitize redirect URIs and improve auth route redirection logic for local mode
- feat/web-oauth: upgrade assent to 0.3 and update OAuth provider adapter signatures and documentation
- feat/web-oauth: conditionally render OAuth provider buttons based on configuration status and display fallback message when none are enabled
- feat/web-oauth: standardize endpoint URL configuration and simplify OAuth redirect URI generation
- feat/web-oauth: add validation to ensure oauth providers return a non-empty email address
- feat/web-oauth: replace dynamic atom conversion with explicit allowlist in OAuth provider lookup
- feat/web-oauth: ignore .env.docker.cloud in .gitignore
- feat/web-oauth: add sign-out link to sidebars and public layout and redesign auth login page
- feat/web-oauth: add RequireCloudMode plug to gate auth routes and hide sign-in UI in local mode
- feat/web-oauth: implement OAuth-based authentication flow and remove signup/org-slug login logic
- feat/web-oauth: replace manual signup with extensible OAuth provider integration and unify authentication flow

## v0.3.72 — 2026-07-21

### What's changed

- fix: harden schema FKs, wire cloud sync, drop unused tables (#37)

## v0.3.71 — 2026-07-17

### What's changed

- feat: add governed agent harness controls (#33)

## v0.3.70 — 2026-07-14

### What's changed

- Merge pull request #35 from aryaminus/refactor/framework-layouts-cleanup
- Add TODO comments for unprotected observability export route
- refactor/framework-layouts-cleanup: remove planning document
- Merge branch 'refactor/framework-layouts-core' of github.com:aryaminus/controlkeel into refactor/framework-layouts-cleanup
- refactor/framework-layouts-cleanup: wire dashboard/observability framework layouts, drop LV wrappers, remove legacy modules
- refactor/framework-layouts-core: add Layouts module and migrate public pages to framework layout

## v0.3.69 — 2026-07-14

### What's changed

- Merge pull request #34 from aryaminus/refactor/framework-layouts-core
- refactor/framework-layouts-cleanup: update layout documentation to specify plug :put_layout usage
- refactor/framework-layouts-core: remove layout configuration from Phoenix controller macro
- refactor/framework-layouts-core: implement core framework layouts and migrate public controllers to use them
- refactor/framework-layouts-core: consolidate layout management by replacing public/root components with a unified layouts module and adding observability support

## v0.3.68 — 2026-07-12

### What's changed

- fix(test): increase MCP integration test call timeout for CI Postgres
- fix(cli): handle keyword-list options for JSON in agents discover command

## v0.3.67 — 2026-07-11

### What's changed

- fix(ci): authenticate verify-channels for GitHub Packages + retry on propagation delay

## v0.3.66 — 2026-07-11

### What's changed

- fix(ci): verify checksums from repo root, not dist/

## v0.3.65 — 2026-07-11

### What's changed

- fix: replace System.cmd pwd shellout with pure Elixir symlink resolution
- fix: add timeout to ToolGroupTracker lookup to prevent MCP server hang
- feat: harden ControlKeel install/attach/release pipeline + fix symlink escape (#32)

## v0.3.64 — 2026-07-09

### What's changed

- fix: update .gitignore to exclude ControlKeel artifacts and remove deprecated controlkeel-operator agent

## v0.3.63 — 2026-07-08

### What's changed

- fix: grep_with_elixir ignored all files under /tmp/ + add ripgrep to pg CI
- fix(test): skip SQLite-only bin-wrapper test on Postgres lane
- fix: increase benchmark_suites.description column to text for Postgres
- fix(test): copy migrated test DB for bin-wrapper subprocess instead of auto-migrating
- fix(test): isolate bin-wrapper subprocess DB to stop shared-DB pollution
- fix(test): make onboarding session assertions relative to starting count
- feat: enhance project root resolution and improve CLI output handling
- chore: fix broken paths in Copilot plugin.json
- fix: CLI --json flag ignored for findings/proofs/benchmarks + stale hook flag
- fix: close review findings on refat branch
- 18th pass: prune stale schemas, APIs, benchmarks, deployment writes
- feat(skill-evolution): close Self-Harness validation loop
- 17th pass (Batch 4): remove redundant Semgrep, relocate deepsec scanner
- 17th pass: remove dead modules, dedup scanner/MCP helpers, tighten visibility
- refactor: strip dead analytics events, RemoteMonitoring, matcher subsystem, dedup review helpers
- refactor: dedup normalize_metadata, inline trivial wrappers, tighten visibility
- refactor(scanner): extract shared SnippetMaterializer module
- refactor: remove dead APIs, fix stale rule-ids, add missing webhook event
- refactor: clean up benchmark subjects, improve telemetry command documentation, and streamline code policies
- refactor: remove unused benchmark subjects and streamline documentation
- refactor: extract shared helpers to Utils, deduplicate across 11 files
- refactor: remove dead code, tighten visibility, strip Anthropic-specific tier
- refactor(mcp): deduplicate stringify_keys into Utils
- refactor(intent): remove ExecutionBrief.to_map bridge and fetch_value duplication
- refactor: drop dead CircuitBreaker and AgentMonitor GenServers

## v0.3.62 — 2026-07-06

### What's changed

- refactor: group cloud telemetry and usage modules into namespaces
- refactor: reorganize lib/controlkeel structure
- refactor: consolidate scattered modules into domain subdirectories

## v0.3.61 — 2026-07-06

### What's changed

- refactor: move 4 modules into existing domain subdirectories
- refactor: move 6 ops/infrastructure modules into Ops namespace
- refactor: move 5 CLI-related modules into CLI namespace
- refactor: move 6 agent modules into Agent namespace
- refactor: move 5 project/workspace modules into Project namespace

## v0.3.60 — 2026-07-06

### What's changed

- Merge origin/main: release v0.3.59
- Merge origin/main: integrate public/dashboard layout refactors
- refactor: move 6 standalone modules into domain subdirectories
- refactor: move 7 top-level modules into Runtime and Mission namespaces
- refactor: move DecisionGates and GovernedManifest into Mission namespace
- feat: add decision-driven governance, MCP tool-poisoning scanner, and modern skill frontmatter

## v0.3.59 — 2026-07-06

### What's changed

- Merge pull request #31 from aryaminus/refactor/public-layout
- Merge pull request #29 from aryaminus/refactor/dashboard-layout
- refactor/public-layout: replace navigate with href for home links in auth and signup live views
- refactor/public-layout: replace local endpoint_config helper with direct call to ControlKeelWeb.Endpoint.config
- refactor/public-layout: remove back to dashboard link from signup live view
- refactor/public-layout: open GitHub repository link in a new tab with secure rel attributes
- refactor/public-layout: open GitHub link in new tab with security attributes
- refactor/public-layout: migrate root layout to dedicated RootLayout module and update auth flow navigation
- refactor/public-layout: migrate home page dashboard metrics to dedicated DashboardLive view
- refactor/public-layout: implement public layout and overhaul getting started page with installation channels
- refactor/dashboard-layout: migrate all dashboard pages to use DashboardLayout.dashboard component
- refactor/dashboard-layout: introduce DashboardLayout and migrate existing LiveViews to use it instead of Layouts.app

## v0.3.58 — 2026-07-03

### What's changed

- chore: apply mix format to observability LiveViews and templates

## v0.3.57 — 2026-07-03

### What's changed

- fix(ci): pin macOS release build to macos-14

## v0.3.56 — 2026-07-03

### What's changed

- fix: idempotent SQLite migrations + ck_skill_load output schema (#28)
- Merge pull request #26 from aryaminus/refactor/obs-subroutes
- refactor/obs-subroutes: enforce workspace scoping for benchmark draft status updates and add error handling to UI
- refactor/obs-subroutes: fix the date and time helper
- refactor/obs-subroutes: update NaiveDateTime formatting to exclude UTC suffix
- refactor/obs-subroutes: consolidate neutral pill class into FormatHelpers module to reduce duplication across LiveViews
- refactor/obs-subroutes: enhance datetime formatting to handle NaiveDateTime in format_datetime function
- refactor/obs-subroutes: fix linting
- refactor/obs-subroutes: add scrollable containers to observability memory and timeline views
- refactor/obs-subroutes: consolidate datetime formatting into new FormatHelpers module
- refactor/obs-subroutes: implement ObservabilitySessionLayout and add command pills across observability pages
- refactor/obs-subroutes: replace global layouts with ObservabilityLayout and integrate CommandPill across observability live views
- Merge pull request #25 from aryaminus/refactor/observability-web
- refactor/observability-web: update recommendations description for clarity and actionability
- refactor/observability-web: update observability overview to limit workspace overview and scope recent runs to the latest workspace
- refactor/observability-web: migrate CommandPill from `__using__` macro to `on_mount` lifecycle hook
- refactor/observability-web: add observability trends date range selection and support rejection reasons in findings browser
- refactor/observability-web: improve observability layout formatting and add component tests for CommandPill and RecentSessions
- refactor/observability-web: add CommandPill component with clipboard copy functionality to observability views
- refactor/observability-web: overhaul observability overview dashboard and replace SessionComponents with RecentSessions component
- refactor/observability-web: standardize observability page headers, remove redundant navigation links, and format recommendations as bulleted lists.
- refactor/observability-web: add active state highlighting to observability navigation links
- refactor/observability-web: introduce ObservabilityLayout component and migrate observability LiveViews to use it
- refactor/observability-web: replace custom CSS classes with Tailwind utility classes across observability LiveView components
- refactor/observability-web: restyle observabilty problem page

## v0.3.55 — 2026-06-15

### What's changed

- fix(npm): de-obfuscate installer URLs (Socket urlStrings alert) (#16)
- chore(docker): bump base image to Debian trixie (supersedes #2) (#15)
- feat: decision lineage, snapshots, precedent & learning-loop closure (#14)

## v0.3.54 — 2026-06-14

### What's changed

- docs: update documentation for clarity and completeness, add control plane claim matrix
- fix: harden memory idempotence, API scoping, cloud sync evidence, review UX

## v0.3.53 — 2026-06-14

### What's changed

- fix(attach): emit portable MCP commands for global host configs

## v0.3.52 — 2026-06-13

### What's changed

- Merge pull request #12 from aryaminus/refactor/proofs-web
- refactor/proofs-web: improve organization ID handling and enhance bundle retrieval logic
- refactor/proofs-web: remove footer slot from table component
- refactor/proofs-web: remove header component from main layout
- refactor/proofs-web: enhance proof browser UI with status badges for risk, verification, and runtime integrity metrics
- refactor/proofs-web: add org-based access control and inline not-found states to proof browser detail view
- refactor/proofs-web: add reset filter button and fix deploy_ready filter serialization
- refactor/proofs-web: replace legacy CSS classes with Tailwind utility classes in ProofBrowserLive view
- refactor/skills-web: add footer slot to table component and update proof browser UI layout

## v0.3.51 — 2026-06-08

### What's changed

- Merge pull request #10 from aryaminus/refactor/skills-web
- refactor/skills-web: improve HTML structure and enhance formatting functions in AvailableInstallComponents
- refactor/skills-web: update provider status display and improve project root input styling
- refactor/skills-web: initialize skill and target search in assign_analysis
- refactor/skills-web*: fix indentation of
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/skills-web
- test: fix test code according to the new changes
- refactor/skills-web: redesign skills studio layout
- refactor/skills-web: integrate enhanced diagnostics
- refactor/skills-web: implement filtering for skills and targets in SkillsLive and add available install component.
- refactor/skills-web: add provider and registry status components to home page
- refactor/skills-web: enhance UI components and replace with tailwind
- refactor/skills-web: skills warning and error label alignment

## v0.3.50 — 2026-06-07

### What's changed

- test(binding): cover dev_or_build_path? guard branches
- fix(runtime): seed project DB from legacy global DB on first boot
- test(mission): assert workspace reuse on duplicate project name
- fix(onboarding): drop dead project_name_taken error match
- fix(binding): avoid hard-coding dev/build paths in MCP wrapper
- fix(mcp): pass effective_skills through audit_full merge
- fix(mission): refactor persist_launch_plan to handle existing workspaces
- fix(codex): use repo-local hook paths instead of $HOME for project-scoped attach
- fix(runtime): add busy_timeout for SQLite lock handling in production
- feat(mcp): ensure required skill tools are always exposed in tool_schemas/1 feat(project_binding): update unwrap_burrito_sibling to correctly resolve native binary path test(skills): add tests for repo_hook_command scope resolution and fallback behavior
- fix(mcp): report runtime version in initialize serverInfo

## v0.3.49 — 2026-06-06

### What's changed

- test(setup): isolate MCP wrapper PATH resolution on CI

## v0.3.48 — 2026-06-06

### What's changed

- fix(setup): detect non-runnable MCP wrapper shims
- fix(skills): clarify duplicate token warning
- fix(cli): reduce skill token overhead
- fix(setup): isolate fresh project runtime state
- fix(migrations): use explicit column lists in SQLite table rebuilds

## v0.3.47 — 2026-06-05

### What's changed

- Add with-vs-without-CK benchmark comparison with cost/time/token deltas
- Revise ControlKeel description for clarity
- Refine README description for ControlKeel
- Revise descriptions in README for clarity

## v0.3.46 — 2026-06-05

### What's changed

- Refactor documentation and UI terminology for clarity and consistency

## v0.3.45 — 2026-06-05

### What's changed

- fix(ci): add --repo flag to gh release upload in sign-release job

## v0.3.44 — 2026-06-05

### What's changed

- fix(test): use DateTime structs for Postgres-compatible insert_all
- fix(maintenance): use to_string comparison for adapter type check
- fix(npm): repair broken regex in cosign path lookup split()
- fix(audit): proof metadata, verification scoring, porcelain filter, attach metadata, install signing, DB safety
- fix(audit): proof metadata, verification scoring, porcelain filter, attach metadata, install signing, DB safety
- fix(cli): honor JSON diagnostics and clean detach artifacts safely
- feat: cosign signing, database maintenance, session event TTL, SQLite VACUUM
- fix(detach): resolve stored agent key and remove the MCP registration

## v0.3.43 — 2026-06-04

### What's changed

- fix: full-potential attach, skill sync, checksum parity, doctor skill consistency
- fix(doctor): keep top-level status "ok"; surface health via install_health
- fix(skills): prune CK's stale skills on re-install, never user-authored ones
- feat(doctor): add install-health checks (git, gitignore, MCP, drift)
- fix(install): verify SHA-256 checksum in shell and PowerShell installers
- fix: gitignore every artifact CK writes into a user repo
- fix: route git shell-outs through crash-safe ControlKeel.Git wrapper
- fix: harden git_context proof capture against missing git and stderr noise

## v0.3.42 — 2026-06-04

### What's changed

- feat: capture git HEAD SHA and working tree state in proof records
- feat: verifiable proof, loop diagnostics, skill eval metadata

## v0.3.41 — 2026-06-04

### What's changed

- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- feat: add agent spec metadata bridge
- feat: add semantic drift scanner guardrails
- feat: enhance review submission with semantic change tracking and governance rules

## v0.3.40 — 2026-06-04

### What's changed

- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- fix: correct dogfood follow-up scope
- fix(self_host): deterministic tar.gz sha256 by zeroing gzip MTIME header

## v0.3.39 — 2026-06-04

### What's changed

- fix: 3 runtime bugs + 2 flaky test assertions from full-suite run
- fix(dogfood): 3 runtime bugs found during full-surface dogfood
- refactor(cli): eliminate 4 more dual-render blocks with render_format/3
- refactor(cli): eliminate 29 dual-render case format do blocks with render_format/3
- feat(annotations+exporter): complete annotation table + cloudflare host module
- Merge refactor/ck-loop-hardening into main
- fix(mcp): normalize advisory to object, fix nullable context_pack fields
- fix(mcp): correct output schema types for nullable and nullable_object fields
- feat(policy-packs): enrich healthcare/finance/education with actionable domain rules
- feat(governance): finish bounded retention, ai_tools, and MCP dedup follow-ups
- fix(mcp): allow object-shaped validate finding locations
- fix(governance): close branch-review blockers before merge
- feat(mcp): return tool execution failures as isError results (Tier B)
- feat(mcp): conservative read-only/destructive tool annotations (Tier A.2)
- test(skills): regression net — every export target produces a plan (Tier A)
- fix: bounded host/SDK/doc parity fixes (Slice P3-G safe fixes)
- feat(memory): detail_level verbosity knob + retention mechanism (Slice P2-F)
- fix(scanner): reliability hardening of the core value prop (Slice P2-E)
- fix(mcp): correct ck_context_pack + ck_execute_code outputSchemas + drift guard (Slice P1-D)
- feat(router): close the learning loop into routing (Slice P1-C)
- feat(sandbox): real runner image, opt-in host-exec enforcement, fail-fast (Slice P0-A)
- feat(findings): agent-callable finding disposition (Slice P0-B of loop-hardening)
- chore(cleanup): remove verified-dead code (Slice 0 of loop-hardening)
- fix: restore deleted exporter modules, eliminate all compiler warnings
- fix(cli): restore 11 command handlers lost in slices 8/9 refactor

## v0.3.38 — 2026-06-02

### What's changed

- docs: add text fence to README bootstrap snippet
- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- feat: slices 7+9+11+12 - CLI parser, exporter targets, plugin registry, sandbox preflight
- feat: slices 4+6+partial-7 - persist tool groups, task/session MCP tools, CLI parser module
- feat: slices 1+3 - MCP outputSchema for all 54 tools, --json consistency
- feat: slices 2+5 - JSON error envelopes, log suppression, shared tool group mapping

## v0.3.37 — 2026-06-02

### What's changed

- Merge pull request #6 from aryaminus/refactor/onboarding-page
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/onboarding-page
- fix(postgres): resolve GROUP BY grouping_error in count_vulnerability_metadata
- refactor/onboarding-page: handle Windows-style line endings when counting key features in router
- refactor/onboarding-page: update missions index to display all sessions and add corresponding integration test
- refactor/onboarding-page: handle missing mission sessions and improve formatting in onboarding live view
- refactor/onboarding-page: remove unused split_list helper function from intent router
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/onboarding-page
- refactor/onboarding-page: update UI assertions, refine boundary constraints, and add duplicate project name/continuation tests to onboarding
- refactor/onboarding-page: prevent duplicate mission project names with validation and error handling
- refactor/onboarding-page: add recent sessions dropdown to onboarding and implement mission selection logic
- refactor/onboarding-page: improve boundary summary display and simplify constraints handling
- refactor/onboarding-page: enhance project name validation and update UI to display acceptance criteria
- refactor/onboarding-page: implement missions dashboard and migrate onboarding route to /missions/start
- refactor/onboarding-page: simplify onboarding layout and enhance validation feedback messages
- refactor/onboarding-page: introduce ProviderStatusComponents and integrate into home view

## v0.3.36 — 2026-06-02

### What's changed

- fix(ci): update workflow versions and resolve vs code extension warnings

## v0.3.35 — 2026-06-02

### What's changed

- fix(tests): format project_root assignment for improved readability
- fix(hooks): update codex hook generation to use global path instead of repo path
- Revert "fix: improve MCP connection stability and optimize precommit performance"
- fix: improve MCP connection stability and optimize precommit performance
- fix: update hook commands to use repo_hook_command for consistency
- fix: update hook commands to use repo_hook_command for consistency
- feat: add opt-in agent envelope for web API
- fix: handle bin/controlkeel parse errors cleanly
- fix: make adaptive MCP tool groups learn usage
- chore: clean whitespace, add CK companion instructions to AGENTS.md
- fix: envelope interceptor requires both status+data, bin uses execute/1
- feat: standardize --json success output with stable envelope
- feat: add CLI catalog, scoped help, JSON error envelope, doctor, and capabilities
- refactor: simplify CLI config handling and remove legacy support; update tests accordingly
- feat: add documentation for adaptive tool groups, API reference, CLI reference, autonomy and findings, control plane architecture, large codebase patterns, and QA validation guide; update .gitignore for antigravitycli
- Refactor agent_router.ex by removing unnecessary blank lines; add "ck_tool_health" capability to protocol_interop.ex
- fix: reorder condition in candidate assignment for clarity
- chore: align structure to standard elixir conventions, move local dbs to priv/repo
- docs: remove links to deleted documentation files
- chore(cleanup): remove remaining dead code and policy training references
- chore(cleanup): remove unused ck.policy mix task
- test(cleanup): remove redundant tests while maintaining essential coverage
- chore(cleanup): remove non-essential documentation and restore web modules
- chore: aggressive cleanup of unused modules, dead marketing pages, and policy training subsystem
- test(hooks): fix skills test to assert on generated hook paths and isolate bin environment

## v0.3.34 — 2026-05-31

### What's changed

- refactor: update demo script for clarity and conciseness
- fix: update checklist and one-pager formatting for clarity and consistency
- feat: update URLs and improve documentation for ControlKeel Studio AI app
- feat: update environment configuration and improve error handling in ControlKeel Studio
- feat: initialize ControlKeel Studio with React, Tailwind CSS, and Vite
- feat(hackathon): surface full ControlKeel platform in Studio
- fix: handle protobuf response conversion in tool-call trace extraction
- fix(hackathon): make AI Studio prompt build-ready and app CK-first
- chore(hackathon): align all demo files to ControlKeel Studio
- feat(hackathon): make ControlKeel Studio robust and product-ready
- fix: Mission Control pages work on Cloud Run
- feat(hackathon): make ControlKeel Studio robust and product-ready
- fix(hackathon): Dockerfile runtime deps + ONE_PAGER with live Cloud Run URLs
- fix(hackathon): graceful fallback when Gemini rate-limited
- feat(hackathon): add GDG Stanford hackathon demo for Cloud Run + Gemini
- feat(api): add endpoints for creating findings and memory records

## v0.3.33 — 2026-05-30

### What's changed

- fix(postgres): resolve GROUP BY grouping_error in count_vulnerability_metadata
- fix(postgres): use database-specific JSON fragments for GROUP BY clauses
- fix(postgres): use raw SQL fragment for GROUP BY to avoid parameterization conflicts
- fix(postgres): resolve GROUP BY and datetime parameter issues
- fix(postgres): parameterize string literal in JSON coalesce function
- fix(postgres): resolve JSON query parameterization and string truncation issues
- fix(migrations): increase memory_records text fields to support longer content
- feat(migrations): increase content size for benchmark_scenarios table in SQLite
- fix(migrations): use PostgreSQL-compatible random function for proxy_token generation
- feat(migrations): add proxy_token to sessions and enhance full-text search for findings and tasks
- fix(tests): improve tampering tests for payload and signature in AuthToken verification
- fix(database): rename ECTO_ADAPTER to CK_DB_ADAPTER for consistency across CI and configuration
- fix(ci): update controlkeel-sdk build command to use npm run build
- feat(agent_execution): enhance task processing with input reference management and sorting feat(ck_validate): include trust policy advisory in validation results feat(planner): add trust policy handling and aggregate task marking for releases feat(skills): add continuity skill to skills list docs(challenge): introduce new challenge skill for adversarial review of plans
- feat(migrations): add provenance fields to findings and RLM fields to tasks feat(tools): implement ck_result_peek tool for accessing stdout of completed runs feat(agent): enhance agent execution with stdout writing and loop detection feat(agent_router): add context_window_k to agent configurations feat(ck_context_pack): support excluding IDs and counting hits in context pack feat(mission): extend findings with references to related findings
- docs(planning): add structural planning and agentic patterns from industry insights
- docs(governance): add AI-generated issue/PR quality controls
- feat(skills): add continuity skill for codebase pattern registry
- docs(deployment): move scenario docs to docs/ and bring all sections current
- test(deployment): close SDK, MCP, and cloud-agent scenario gaps
- docs(cloud): update stale tracker TL;DR, HEAD pin, open question, test count
- docs(cloud): avoid stale HEAD pin in readiness tracker
- docs(cloud): pin readiness remediation HEAD
- fix(cloud): close readiness review gaps
- docs(deployment): add deployment scenarios verification status

## v0.3.32 — 2026-05-28

### What's changed

- fix(cloud-sync): hardening pass closing all 10 post-merge findings

## v0.3.31 — 2026-05-28

### What's changed

Cloud-sync hardening — closes four high-severity blocking findings and six
medium issues raised in post-merge review of v0.3.30's `Cloud.Sync`,
`Cloud.SyncEngine`, and `CloudSyncController`.

- fix(cloud-sync, security): close `CK-CLOUD-SYNC-001`. `Cloud.Sync.serialize_record/1`
  now uses a per-schema `sync_fields/0` allowlist instead of `Map.drop` on
  preloads — anything not in the allowlist never ships. Free-form fields
  (`Memory.Record.body`, `Finding.plain_message`, `Review.submission_body`,
  task/agent `metadata`, etc.) are tagged `{:redact, _}` and pass through
  `Cloud.Redactor.redact_value/1`, which scrubs Anthropic/OpenAI `sk-*` keys,
  GitHub PATs, `Authorization: Bearer` headers, and env-style
  `token=`/`secret=`/`api_key=` assignments. Envelopes now stamp both
  `sync_protocol_version` and `redaction_policy_version`.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-002`. Migration
  `20260528270000` adds `external_id` (`ses_<ulid>`) and `synced_at` to the
  `sessions` table, backfilling existing rows with `ses_legacy_<id>`. Without
  this, every other syncable kind's foreign-key chain was broken.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-003`. `do_upsert` for
  append-only kinds now compares the incoming `updated_at` against
  `local.updated_at` instead of skipping on `synced_at != nil`. Cloud-side
  status changes (e.g., `open → blocked`) finally propagate to local.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-004`. `WorkspaceAgent.changeset`
  now casts `:lock_version` (it was missing from the cast list, which silently
  dropped every bump). Optimistic concurrency on agents is real now.
- fix(cloud-sync): close `CK-CLOUD-SYNC-005`/`006`/`007`/`008`. `SyncEngine`
  state-machine rewrite: `state.syncing` actually flips during do_sync so the
  `:already_syncing` guard isn't dead code; the first-ever pull uses the unix
  epoch as the cursor (was: skipped entirely); `last_synced_at` only advances
  on `{:ok, _}` from `do_sync` (was: advanced on failure, leaking records);
  workspace resolution goes through `WorkspaceKeyRegistry.fetch/1` instead of
  `Workspace |> limit(1)`. Unmapped workspaces return `:workspace_not_enrolled`.
- fix(cloud-sync): close `CK-CLOUD-SYNC-009`. `CloudSyncController` drops the
  string-id silent-empty guard. The token's cloud `workspace_id` (string) is
  now resolved to a local `mission_workspace_id` via `WorkspaceKeyRegistry.fetch/1`
  in a new `resolve_db_workspace_id` plug; unmapped tokens get a 404 with a
  clear error. Pull now collects **all four** append-only kinds (findings,
  reviews, session_digests, memory_records) instead of just findings.
- fix(cloud-sync): close `CK-CLOUD-SYNC-010`. `payload_to_attrs` now collects
  unknown fields and logs them at warning level instead of silently dropping
  via `String.to_existing_atom` rescue. Envelope-protocol version mismatch is
  surfaced via `Logger.warning` so version skew is visible.
- fix(cloud-sync): wrap `upsert_batch/2` in `Repo.transaction` so partial
  batch failures roll back; replace per-record changeset writes in `mark_synced/1`
  with a grouped `Repo.update_all` (one round-trip per schema, not per record);
  enforce `max_batch_bytes` (default 8 MB) via JSON-encoded size check.
- test: 24 new tests covering each of the above fixes — round-trip status
  propagation, redactor pattern coverage, workspace_agent lock_version actually
  bumps in the DB, syncing-flag guard fires, first-tick pull uses epoch,
  cursor doesn't advance on failure, unmapped workspace 404s, protocol-version
  mismatch logs. 1951/1951 tests, 0 failures.

### Migration notes

`mix ecto.migrate` applies `20260528270000_add_external_id_to_sessions.exs`.
Backfill happens inline; no manual step required.

## v0.3.30 — 2026-05-28

### What's changed

- feat(cloud-sync): bidirectional cloud sync for governance records.
  New `Cloud.Sync` module collects unsynced findings, memory records,
  reviews, and session digests; serializes them into idempotent envelopes
  keyed by `external_id`; pushes to the cloud endpoint; and pulls remote
  records with local upsert. `Cloud.SyncEngine` GenServer orchestrates
  periodic push/pull (dormant when no `cloud_sync_endpoint` is configured).
  `CloudSyncController` exposes `POST /cloud/v1/sync/push` and
  `POST /cloud/v1/sync/pull` with bearer token auth and 500-record batch limit.
- feat(cloud-sync): workspace-scoped PubSub via `CopilotChannel.subscribe_workspace/1`
  and `broadcast_workspace/3` — topic `ck_workspace:<id>` enables multi-user
  realtime without session-level scoping.
- feat(cli): three new CLI commands — `controlkeel cloud push`,
  `controlkeel cloud pull`, `controlkeel cloud migrate` — for manual sync
  trigger and migration check.
- feat(db): migrations `20260528250000` and `20260528260000` add `external_id`
  (ULID-prefixed: `f_`, `rev_`, `sd_`, `mem_`) + `synced_at` to findings,
  memory_records, session_digests, and reviews; `lock_version` (optimistic
  concurrency) on sessions, tasks, and workspace_agents.

### Migration notes

Run `mix ecto.migrate` to apply the two new migrations. Existing records
receive auto-generated `external_id` values and `lock_version` defaults to 1.
No data loss; columns are nullable during transition.

## v0.3.29 — 2026-05-28

### What's changed

- feat(digest): new `ck_session_digest` MCP tool and `SessionDigest` module.
  Generates condensed, human-scannable digests of what happened in a session —
  tasks completed, findings raised, budget spent, reviews pending, and notable
  highlights. Three digest types: session, daily, shift_change. Sets
  `needs_attention` flag when blocked findings, pending reviews, >80% budget
  consumption, or tech-debt accumulation signals are detected. Also exposes
  `avg_task_duration_seconds` and `tasks_per_hour` in `metadata` so operators
  can observe time-gained vs output-gained without CK pushing either dimension.
- feat(techdebt): new `Governance.TechDebtDetector` and `CK-TECHDEBT-001/002`
  rule family surfaced through `ck_session_digest`. Detects (1) repeated
  patches on the same `Finding.metadata["path"]` across recent sessions
  without an intervening refactor/cleanup commit on that path, and (2) the
  same `rule_id` recurring across ≥3 sessions in the workspace. No new MCP
  tool, no schema migration — reuses `Finding.metadata` and the existing
  `SessionDigest.metadata` map. Inspired by Dax Raad's observation that AI
  code generation mutes the "guilt" of writing a hack, so the muted signal
  has to come from somewhere else.
- feat(rollback): new `ck_rollback` MCP tool and `RollbackExecutor` module.
  Makes rollback executable, not just advisory. Records a git checkpoint
  (commit SHA) before each task via `checkpoint` mode, and provides `execute`
  mode to revert an agent's work with a single action. Safety-checked: refuses
  if downstream completed tasks depend on the changes. Creates an audit finding
  (`CK-ROLLBACK-001`) on every rollback. Inspired by "you need easy rollback."
- feat(agents): new `ck_workspace_agent` MCP tool and workspace agent roles.
  Formalizes agent-role scoping for orgs adopting a forward-deployed-engineer
  pattern, without asserting that pattern as inevitable: `primary` (a single
  maintained agent per workspace), `specialized` (domain-scoped, multiple
  allowed), and `ephemeral` (short-lived task runners). Health monitoring,
  budget tracking, and retirement lifecycle.
- feat(copilot): new `ck_copilot` MCP tool and `CopilotChannel` GenServer.
  Real-time collaborative channel where human actions (viewing, editing,
  approving, commenting) stream to the agent via PubSub without polling. ETS-
  backed event history with auto-pruning. Added to supervision tree. Inspired
  by "build software for humans and agents to use together."
- feat(saas): new `ck_external_service` MCP tool and `ExternalServiceTracker`.
  Tracks and governs agent interactions with external SaaS APIs. Per-service
  rate limiting, cost attribution, latency tracking, and automatic PII
  redaction (tokens, emails) from endpoints. Summary, rate_limit_status, and
  top_services views. Inspired by "agents will create massive new demand for
  SaaS."
- fix(mcp): eliminate 4 compile warnings that were leaking to stdout and
  causing intermittent MCP handshake issues (grouped `run_command/2` clauses
  in cli.ex, grouped `write_target/5` clauses in exporter.ex, removed unused
  default in cloud_runtime_callback_controller.ex).
- fix(agents): replace the over-broad `(workspace_id, role)` unique index on
  `workspace_agents` with a partial unique index scoped to active `primary`
  agents. The original constraint silently blocked the documented case of
  registering multiple specialized or ephemeral agents per workspace.
- fix(db): apply pending migrations for `external_id` on tasks and
  `workspace_github_repos`.

- fix(mcp): update `ck_review_submit` description to name the structured planning fields
  (`research_summary`, `options_considered`, `selected_option`, etc.) that the plan-quality
  scorer evaluates — agents reading the tool description will no longer package everything
  into `submission_body` and get scored weak on first attempts (CK-REVIEW-SCHEMA-002).

## v0.3.28 — 2026-05-28

### What's changed

- feat(cloud): authorize cloud run package creation by org/role
  (`Accounts.authorize_cloud_execution/2`); CLI accepts `--user-id`.
- feat(cloud): link enrolled cloud workspaces to mission workspaces via
  invitation binding. `controlkeel cloud connect --enroll` now reports
  `mission_workspace_id`; `WorkspaceKeyRegistry.fetch_by_mission_workspace/1`.
- feat(cloud): capture git remote/branch/commit_sha on cloud run packages.
  `controlkeel run cloud-agent` shells out to git and accepts
  `--repo-url` / `--branch` / `--commit-sha` overrides.
- feat(cloud): runtime dispatcher seam. New `RuntimeDispatcher` behavior +
  `Manual` default; runtime modules register via `:cloud_dispatchers`
  application config. `controlkeel run cloud-agent --dispatch` chains
  create and dispatch in one command.
- feat(cloud): cloud runtime callbacks accept an optional `findings[]`
  array. `RuntimeContext.ingest_findings/2` persists each finding on the
  package's session tagged with cloud provenance metadata.
- feat(cloud): observable run packages on `/cloud/projects/:ws_id` — new
  "Cloud run packages" card listing each package's status, runtime,
  revision, budget, and timestamps.
- feat(cloud): stable user-facing identifiers — `pkg_<ulid>` on cloud run
  packages, `task_<ulid>` on tasks. Both auto-generated, caller-
  overridable, unique-enforced. Lookup helpers
  `RuntimeContext.get_by_external_id/1` and
  `Mission.get_task_by_external_id/1`.
- feat(cloud): workspace ↔ GitHub repo bindings. New
  `workspace_github_repos` schema + Mission API + CLI (`controlkeel
  govern bind/unbind/list github`). Bound repos ride along in the run
  package payload so downstream runtimes know which repositories to
  fetch.
- feat(cloud): cross-org isolation regression test pins the boundary
  across authz, `list_for_org`, `list_for_workspace`, and the cloud
  projects LiveView.
- fix(cloud): cloud projects table head/body column mismatch and an
  awkward `if/do:` pipe in `mount_index` / `handle_info`.
- chore(format): apply mix format to drift across migrations and tests.
- docs(cloud): callback token lifecycle moduledocs aligned with the
  valid-until-terminal implementation; telemetry controller docs describe
  signed ed25519 AuthToken verification.
- docs(cloud): new `docs/cloud-parity-matrix.md` user-perspective audit
  of every cloud surface with status markers and finding cross-refs.

## v0.3.27 — 2026-05-26

### What's changed

- feat(antigravity): add Antigravity CLI and IDE support with governance bundles
- feat(host-parity): fix crashes and close surface gaps across 26 attachable hosts
- feat(cloud): expand hosted governance surfaces
- feat(setup): strengthen one-line ControlKeel attach flow
- test: update assertions for Claude settings in skills test

## v0.3.26 — 2026-05-25

### What's changed

- feat: implement multi-tenant workspace key management
- feat: enhance findings and policy studio live views with rejection handling and tool policies
- feat(api): add workspace tool policy management and NHI audit event endpoints
- feat: implement JetStream adapter for durable pub/sub queues and add visibility to memory records
- feat: implement Tier 2 deferred items — behavioral baselining, air-gapped pack, NHI lifecycle
- feat: implement Tier 1 deferred items — fallback chain, compliance templates, workspace tool policies
- feat(cloud): update cloud enterprise roadmap with shipped status and deferred items
- feat(agents): add 'agents discover' command for scanning agent-host configurations
- feat(saml): implement SAML authentication flow with controller, client, and CLI support
- feat(auth): implement OIDC authentication flow with session management
- feat: Implement org identity provider configuration and audit export functionality
- feat(cloud): implement runtime context for cloud run packages
- Add comprehensive tests for CLI commands, cloud guardrails, MCP audit logs, policies, and invitation handling
- feat: Add CloudTelemetryLive for monitoring telemetry ingestion health and funnel metrics
- feat: Implement cloud telemetry ingestion and authentication
- Add tests for ControlKeel Cloud components
- feat(docs): enhance cloud enterprise roadmap with positioning, priority elevation, and market validation updates
- feat(docs): expand cloud enterprise roadmap with governance framework and security gates
- feat(docs): update architectural decisions section with resolved defaults and implications
- feat(docs): add open questions and phase acceptance gates to cloud enterprise roadmap
- feat(docs): add cloud-capable runtime surfaces section to support matrix
- feat(docs): enhance cloud and team governance documentation with roadmap and telemetry sync details
- feat(tests): add skill directory name assertion and helper function
- feat: add session list and switch commands with corresponding help documentation
- chore: remove stale research and strategy docs

## v0.3.25 — 2026-05-22

### What's changed

- docs: refine README for clarity and consistency in descriptions
- docs: tighten README opening paragraph
- fix: add ck_engineer_mirror to protocol test and apply formatter changes
- feat: engineer daily mirror + human-side prompt-quality outcomes

## v0.3.24 — 2026-05-22

### What's changed

- fix: eliminate Exqlite sandbox disconnect error in LiveView tests

## v0.3.23 — 2026-05-22

### What's changed

- fix: suppress noisy spawn errors when deepsec cd directory doesn't exist
- fix: repair release readiness proof selection
- feat: enhance npm publishing with trusted publishing and registry configuration
- feat: enhance stream_scan functionality and add tests for findings emission

## v0.3.22 — 2026-05-21

### What's changed

- Merge pull request #3 from aryaminus/refactor/web-homepage
- refactor/web-homepage: remove unused runtime policy section from layout
- refactor/web-homepage: add TODO to replace client-side active link with LiveView-driven approach
- fea/web-homepaget: restore vanilla css
- refactor/web-homepage: move format_percent and format_number functions to PageHTML module
- Update assets/js/app.js
- test: update skills live test
- test: add tests for install page rendering
- refactor/web-homepage: enhance install page layout and styling
- refactor/web-homepage: add module and route for ControlKeel installation, policy and observability
- refactor/web-homepage: implement dynamic sidebar link highlighting and enhance home page layout
- refactor/web-homepage: Refactor layout and home page to enhance dashboard presentation

## v0.3.21 — 2026-05-19

### What's changed

- feat: enhance entropy detection and add tests for credential handling
- chore: replace synthetic seed data with no-op seeds file
- refactor: apply terminology cleanup to source and tests
- chore: remove example files and update remaining demo-script references
- docs: clean up imprecise terminology across docs and remove demo-script
- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- docs: refine documentation on context file usage, SDK vs MCP cost implications, and signal family vocabulary
- feat: update version in plugin.json and enhance documentation for observability and budget alerts
- feat: update documentation and implementation for observability and budget alerts
- docs: add large codebase patterns and best practices for agent deployment
- docs: enhance documentation on SDK vs MCP cost implications and best practices for coding agents
- docs: add production signal observability guidance
- docs: expand agent observability guidance
- feat: enhance benchmark and observability documentation with eval design principles and sampling guidelines
- docs: clarify event-sourced harness posture
- feat: preview Workshop observability snapshots
- style: format MCP resilience changes
- chore: prune stale integration artifacts and harden MCP startup
- Remove legacy deep research report and HELM plan documents; update product strategy plan to clarify focus on current strategy and removal of historical materials.
- feat: enhance virtual workspace with ranking and orientation metadata for search results

## v0.3.20 — 2026-05-07

### What's changed

- docs: enhance documentation with clarity on governed engineering game loop and agentic work
- docs: replace stale release checkpoints with refreshable template
- fix: copy Python runtime executables in generated Dockerfile
- fix: align deployment templates with runtime defaults
- feat: enhance Amp Neo integration with compaction provenance tracking and CK-gated remote-control commands

## v0.3.19 — 2026-05-06

### What's changed

- fix: enhance Zig installation script with caching and retry logic

## v0.3.18 — 2026-05-06

### What's changed

- fix(mcp): fix ToolGroupTracker crash, usage accumulation, and clarify skill references
- chore: re-attach opencode, verify clean AGENTS.md output
- fix(distribution): align Dockerfile with CI, fix npm checksum URL, add Glama docs
- fix(installer): strip broken comment markers without closing --> in sanitize_agents_md
- fix(mcp): harden argument handling and update sync guidance
- feat(amp): enhance Amp Neo integration with updated governance features and documentation
- feat(cli): enhance skills list command to support JSON output format feat(host_audit): implement fallback to GET request for URL checks fix(cli): adjust status command to handle JSON format correctly
- feat(security): add AI tool configuration checks for hardcoded credentials

## v0.3.17 — 2026-05-05

### What's changed

- docs: update governance checklist and enforcement mechanisms in AGENTS.md
- fix(integrations): handle missing deepsec CLI gracefully in tests
- docs: add manual record for governance finding and memory entry
- feat(governance): implement multi-layer safeguards to prevent governance failures
- docs: update governance retrospective with post-implementation actions
- feat(integrations): add deepsec security scanner integration (with governance retrospective)
- Implement feature X to enhance user experience and optimize performance

## v0.3.16 — 2026-05-04

### What's changed

- feat(mcp): enrich tool and property descriptions for Glama TDQS score
- docs: add controlkeel MCP server badge to README

## v0.3.15 — 2026-05-04

### What's changed

- feat: add ToolGroupTracker to application and implement safe calls for adaptive tool group selection
- fix: add standard Apache 2.0 SPDX header to LICENSE for GitHub detection
- docs: update README with adaptive tool groups feature

## v0.3.14 — 2026-05-03

### What's changed

- fix: remove --warnings-as-errors from CI to match local precommit
- feat: enhance documentation for adaptive tool groups and automatic optimization
- feat: Implement adaptive tool group selection and tracking
- feat(token-optimization): update tool groups for improved token savings and documentation
- feat(token-optimization): implement default tool groups configuration and usage examples for token reduction
- feat(mcp): configure tool groups for token optimization; update CLI and tests for new functionality
- feat(token-optimization): complete token overhead audit, multi-host coverage, and config activation
- feat(mcp): enhance skill analysis and token overhead reporting; add duplicate skill diagnostics
- feat(token-audit): implement CK-side tool groups for lazy loading and token savings

## v0.3.13 — 2026-05-02

### What's changed

- fix(ci): handle missing ripgrep in workspace context detection
- fix(mcp): audit and harden discovery, ck_mcp_discover, and ck_skill_validate
- feat(cli): add multica-cloud runtime export command feat(docker): extend sensitive env var checks with suffixes docs(help): update runtime export command documentation with new targets fix(protocol): clarify HTTP transport type description refactor(ck_skill_validate): enhance object validation with additional properties feat(skills): add compatibility for new native integrations across multiple SKILL files
- Enhance documentation on evaluation, governance, and observability
- feat(skills): surface export manifests in doctor output
- feat(skills): write install manifest on export
- feat(mcp): add ck_mcp_discover for MCP server auto-discovery
- fix(security): filter sensitive env vars before forwarding to Docker sandbox
- feat(skills): integrate agent-skills governance patterns into CK skills
- feat(quality): integrate agent-verifier pattern detection into CK
- feat(security): enhance vulnerability taxonomy and remove Strix integration
- chore: remove trailing blank lines in workspace_checkpoint.ex
- feat(skills): add result-schema validation and selective env var exposure
- feat(omnara): add integration analysis and opportunities documentation for ControlKeel
- docs(help): add help topics for worktrees, checkpoints, git workflow, and monitoring
- feat(mcp): register 9 new tools in protocol — worktrees, checkpoints, git, monitoring
- feat(monitoring): add RemoteMonitoring GenServer and ck_monitor_subscribe MCP tool
- feat(git): add governed git workflow with diff/commit/status MCP tools
- feat(worktrees): add ck_worktree_list and ck_worktree_switch MCP tools
- feat(checkpoints): add WorkspaceCheckpoint with create/restore/list and MCP tools
- feat(mission): add TaskCheckpoint CRUD functions
- feat(workspace): add git worktree detection to WorkspaceContext

## v0.3.12 — 2026-05-01

### What's changed

- fix: remove postinstall.js check from CI workflow
- feat: implement lazy download model and enhance security measures for ControlKeel CLI
- docs: streamline explanation in the "Why this exists" section of README
- docs: update README to clarify ControlKeel's role and features

## v0.3.11 — 2026-05-01

### What's changed

- fix: add CI timeouts to prevent 6-hour test hangs
- fix: make observability skill guidance test resilient to empty gitignored dirs

## v0.3.10 — 2026-05-01

### What's changed

- feat: enhance documentation on domain knowledge persistence and agent interaction
- feat: add perf_snapshot persistence to CK memory
- feat: add perf_snapshot observability report and fix test failures
- feat: enhance CLI and MCP modes for improved logging and performance
- feat: add WozCode-inspired tool pattern detection and experience search

## v0.3.9 — 2026-05-01

### What's changed

- fix: version guard only protects plugin bundle; AGENTS.md always written
- fix: harden all host hooks with ck_run + version guard, add local build script
- fix: stop hook sync no longer stomps AGENTS.md or .cursor-plugin hooks
- fix: prevent installed binary from overwriting newer source-synced versions
- perf(db): add composite indexes + SQL aggregate for hot query paths
- feat: enhance README with local observability loop details and CLI commands

## v0.3.8 — 2026-04-30

### What's changed

- fix: make observability skill guidance test CI-safe
- feat: complete observability surface coverage
- chore: sync ControlKeel 0.3.7 surfaces
- feat: strengthen observability learning loop

## v0.3.7 — 2026-04-30

### What's changed

- chore: sync attached ControlKeel surfaces

## v0.3.6 — 2026-04-30

### What's changed

- feat: add ck_observability tool and integrate into MCP protocol
- feat: add local observability feedback loop documentation and commands
- feat: add observability promotions command, UI, and tests
- feat: add observability benchmark history command, UI, and tests
- feat(cli): add new commands for observability benchmarks
- fix: update command paths to handle missing git repository context
- feat: add commands to approve, reject, and archive benchmark drafts with corresponding updates and tests
- feat: add observability regressions command, UI integration, and related tests
- feat: add benchmark draft commands, UI integration, and related tests
- feat: add new observability features including memory quality, trends, and saved eval candidates
- feat: add observability imports command, UI integration, and related tests
- feat: implement observability import with persist option and update related commands and tests
- feat: add observability memory command, context summary, and UI integration
- feat: add observability comparison and timeline commands, UI components, and tests
- feat: add observability costs, eval candidates, and recommendations pages
- feat: add observability import/export commands and overview

## v0.3.5 — 2026-04-29

### What's changed

- fix: update Codex CLI status to verified and clarify checks for sandbox execution
- feat: add observability features and UI components
- fix: update command descriptions for clarity in governance review and submission
- fix: enhance ck_budget check and clarify workflow for delegated implementation
- docs: add cross-runtime continuity verification guide
- test: add cross-runtime continuity tests for budget status and memory source filters
- feat: add source_type and source_id filtering to ck_memory_search
- fix: add ck_budget status mode to check spend without cost inputs
- fix: make skills export/install idempotent with pre-existing destinations
- Refactor MCP tools to resolve session_id from project_root and update input schemas
- feat: Enhance benchmark and cost governance documentation with new guidelines for outcome-first harness loops and multi-agent routing strategies
- feat: Update documentation and security policies, add new packages overview, and enhance .gitignore
- feat: Enhance README and documentation with governance layer details for company context graphs

## v0.3.4 — 2026-04-28

### What's changed

- feat: Add support for Multica native and cloud runtime targets in skill export

## v0.3.3 — 2026-04-28

### What's changed

- feat: Add Multica native and cloud runtime targets to skill catalog
- feat: Enhance skill parsing with owner metadata and content hash computation
- feat: Add Multica integration and content hash to skill definitions
- feat: Add owner field to skill definitions and update related parsing logic
- docs: Update README and support matrix for OpenCode integration details
- Refactor MCP argument handling and tool schemas

## v0.3.2 — 2026-04-28

### What's changed

- feat: Add Warp and Warp Oz integrations
- feat(agent): add support for Devin for Terminal integration with native configuration and hooks
- feat(skill): add handoff skill for session state preservation and background execution
- feat(skills): add align and plan-slice skills for improved project planning and execution
- feat(docs): add details on Pi subagent extensions and their integration with ControlKeel
- feat(tool): add ck_tool_health for governance coverage analysis and implement tests
- feat(docs): enhance benchmark documentation with surface evaluation details and new evaluation script
- feat(agent): add jcode integration with research compatibility and update tests
- feat(docs): update benchmark documentation for clarity on evidence handling and OpenCode procedures
- feat(benchmark): add ck-bounded mode for OpenCode governance and update documentation
- feat(goals): add ck_goal tool for managing durable governed goals and ck_context_pack tool for creating context bundles
- feat(docs): update README and product strategy to clarify ControlKeel's role as software for agents and a company brain for governed delivery
- feat(security): add new rules for mass assignment, rate limiting, sensitive request logging, and IDOR protection
- feat(gdpr): enhance GDPR compliance checks and add new privacy officer domain
- Enhance benchmark subjects and governance harness

## v0.3.1 — 2026-04-26

### What's changed

- feat(review): add alignment context and consulted roles to review packets
- Add Apache-2.0 LICENSE and glama.json for Glama metadata
- Refactor Policy Studio and Proof Browser Live Views to Use Layouts

## v0.2.50 — 2026-04-26

### What's changed

- fix(install): write CLAUDE.md + hooks to project on init/attach

## v0.2.49 — 2026-04-26

### What's changed

- fix(release_smoke): increase timeout and improve process handling

## v0.2.48 — 2026-04-26

### What's changed

- docs(benchmarks): add protocol adapter experiment guidance
- docs(afk): add overnight credibility guidance
- docs(loops): clarify overnight execution posture
- docs(memory): clarify host file memory posture
- docs(integrations): align guarded code execution host surfaces

## v0.2.47 — 2026-04-26

### What's changed

- docs: update ControlKeel workflow guidance
- feat: add guarded code execution tool
- feat: add code-mode governance policy
- fix: avoid stalled plan review waits
- feat: add experience profile support and session hygiene suggestions for cost management
- docs(architecture): enhance planning guidance with interface design and behavior-first focus
- docs(benchmarks): enhance benchmark guidance with premise-refusal and dissatisfaction evals docs(control-plane): clarify task sizing and execution boundaries in architecture fix(exporter): improve context management and planning guidance in exporter module

## v0.2.46 — 2026-04-26

### What's changed

- fix(integrations): avoid stalled review waits and trim context payloads
- chore(cleanup): remove leftover dev mailer config

## v0.2.45 — 2026-04-26

### What's changed

- docs(integrations): clarify benchmark and browser companion guidance
- feat(governance): review GitHub PR URLs directly
- chore(cleanup): remove dead mailer and unused assets

## v0.2.44 — 2026-04-24

### What's changed

- feat(integrations): model dmux as a framework adapter

## v0.2.43 — 2026-04-24

### What's changed

- fix(benchmarks): track repo benchmark subjects for ci
- feat(governance): expand diagnostic findings coverage
- feat(benchmarks): add multi-host comparison workflow

## v0.2.42 — 2026-04-22

### What's changed

- Enhance promotion integrity checks and decision prompts across modules

## v0.2.41 — 2026-04-21

### What's changed

- feat: add diagnostics for daemon role fields in skill metadata and enhance parser validation
- feat: add frontmatter hygiene diagnostics for third-party skills in parser

## v0.2.40 — 2026-04-21

### What's changed

- feat: add interoperability guidelines for external optimizers in benchmarks documentation
- feat: enhance non-server endpoint configuration and update review timeout handling

## v0.2.39 — 2026-04-21

### What's changed

- fix: update documentation for Codex integration and user checkpoints

## v0.2.38 — 2026-04-21

### What's changed

- ci: parallelize release smoke linux and windows builds

## v0.2.37 — 2026-04-20

### What's changed

- fix: soften codex stop hook blocked-findings warning

## v0.2.36 — 2026-04-20

### What's changed

- docs: clarify lean harness guidance for host integrations

## v0.2.35 — 2026-04-20

### What's changed

- test: add comprehensive tests for t3code integration, governance, and runtime conformance
- feat(governance): add canonical event bridge, turn lifecycle, thread state, and budget telemetry
- feat(governance): add approval adapter, idempotency ledger, and remote session claims
- feat(governance): add runtime policy profiles, orchestration event namespace, and wire into recommendations
- feat(integration): promote t3code from alias to first-class attach client
- feat(runtime): add capabilities callback to Runtime behaviour and implement across all runtimes
- feat(docs): enhance documentation on agent integrations, control-plane architecture, and skill package distribution; clarify workflow phases and supply chain considerations

## v0.2.34 — 2026-04-19

### What's changed

- feat(governance): improve code-mode routing and plan-review fallback
- feat(docs): enhance documentation on progressive discovery, human wake-up surfaces, and enterprise control-plane posture feat(core): improve project root resolution logic and enhance advisory status handling test: add tests for CK_PROJECT_ROOT usage in advisory status resolution

## v0.2.33 — 2026-04-19

### What's changed

- fix(mcp): harden launcher fallback and add troubleshooting guidance

## v0.2.32 — 2026-04-19

### What's changed

- feat(cli): add 'attach doctor' command for post-attach verification and health checks
- feat(cli): add status option to watch command and improve error handling for connection failures
- fix(docs): update target from 'codex' to 'opencode' in AGENTS.md and refine setup instructions in README.md
- docs: add one-line setup instructions for ControlKeel in README

## v0.2.31 — 2026-04-18

### What's changed

- feat(runtime): add codex app-server support and sqlite busy retries
- fix(cli): accept positional target for skills export/install subcommands
- fix(test): loosen session_id error message assertion in api_controller_test
- fix: guard jq calls in user-prompt-submit hook against non-JSON context output
- feat: close all Claude integration gaps — write hooks, governance injection, full tool coverage
- feat: add claude-sdk target and SDK integration guidance for Agent SDK
- feat: Add SubagentStart/PostToolUseFailure/ConfigChange/PermissionDenied hooks and fix plugin agent
- feat: Enhance Claude Code integration with full lifecycle hooks, marketplace, and skill metadata
- feat: Enhance Codex CLI integration with lifecycle hooks and configuration updates

## v0.2.30 — 2026-04-18

### What's changed

- chore(registry): align server metadata with 0.2.29 publish

## v0.2.29 — 2026-04-18

### What's changed

- chore(registry): prepare npm package metadata for MCP publish

## v0.2.28 — 2026-04-18

### What's changed

- fix(governance): keep escalated findings human-gated
- Merge branch 'fix/ck-review-store-split'
- fix(mcp): broaden review fallback variants for split runtime contexts
- Merge branch 'fix/ck-review-store-split'
- feat(harness): surface explicit harness principles
- fix(opencode): restore linked CLI execution and tighten governance skill guardrails

## v0.2.27 — 2026-04-18

### What's changed

- feat(update): surface release checks across host agents

## v0.2.26 — 2026-04-17

### What's changed

- docs(cli): add help entries for agent routing and task lifecycle commands
- fix(governance): harden review workflows and runtime host defaults

## v0.2.25 — 2026-04-17

### What's changed

- fix(mcp): prevent review tool endpoint crashes

## v0.2.24 — 2026-04-17

### What's changed

- fix(opencode): mirror legacy config for MCP attach
- fix(opencode): stabilize governed plan-review transport and MCP startup

## v0.2.23 — 2026-04-16

### What's changed

- chore(cursor): align plugin manifest version with app release

## v0.2.22 — 2026-04-16

### What's changed

- fix(governance): auto-resolve matching findings on allow rulings

## v0.2.21 — 2026-04-16

### What's changed

- fix(opencode): harden submit-plan JSON handling in release flows
- docs(opencode): document MCP enabled verification and local attach fallback
- fix(opencode): write enabled MCP entries for local server

## v0.2.20 — 2026-04-16

### What's changed

- fix(mcp): bootstrap installs stdio launcher for CK source; track priv template
- fix(opencode): make local MCP launcher respond under persistent stdio
- fix(cli): force standalone logger output to stderr so `--json` responses stay machine-readable in release flows
- fix(opencode): harden submit-plan JSON parsing and error handling when CLI output includes non-JSON lines

## v0.2.19 — 2026-04-16

### What's changed

- fix(opencode): align native integration with OpenCode surfaces
- feat(hooks): update permission decision for PreToolUse event in ck_copilot_hook.sh

## v0.2.18 — 2026-04-16

### What's changed

- refactor(hooks): remove unused SubagentStop and Stop hooks; enhance logging in ck_copilot_hook.sh
- feat(governance): implement ControlKeel hooks and update version to 0.2.17

## v0.2.17 — 2026-04-16

### What's changed

- Internal maintenance release.

## v0.2.16 — 2026-04-15

### What's changed

- fix(claude): make `attach claude-code` idempotent when MCP server already exists
- fix(mcp): ensure stdio server startup before MCP CLI handoff and improve launcher stdio reliability
- chore(qa): add full Copilot parity script with bounded MCP/attach checks for deterministic audit runs

## v0.2.15 — 2026-04-15

### What's changed

- feat(update): add release-aware upgrade flow

## v0.2.14 — 2026-04-15

### What's changed

- feat(cli): add context and validate commands

## v0.2.13 — 2026-04-15

### What's changed

- fix(mcp): filter mix stdout in bin/controlkeel-mcp for stdio JSON

## v0.2.12 — 2026-04-15

### What's changed

- fix(mcp): stderr logging in CK_MCP_MODE; align Cursor integration docs
- fix(mcp): stdio newline-delimited JSON-RPC per MCP spec
- fix(mcp): handle JSON-RPC 2.0 batches (Cursor handshake)
- fix(mcp): avoid Registry scans on tools/list and resources/list in stdio
- chore(mcp): stderr boot timing, app.start --no-compile, SQLite busy_timeout
- fix(mcp): defer Repo/bus boot so Cursor can finish initialize
- fix(mcp): source-tree launcher uses mix ck.mcp, not release bin
- fix(mcp): dogfood source tree prefers local release/mix over PATH controlkeel
- fix(mcp): prefer local mix release binary over mix ck.mcp when present
- fix(mcp): use IO.binwrite for stdio and binary io opts in reader
- fix(mcp): flush stdout after each framed JSON-RPC response
- fix(mcp): skip Phoenix CodeReloader when CK_MCP_MODE for faster Mix boot
- fix(mcp): defer release migrations until after MCP children start
- fix(mcp): supervise stdio server before Repo under CK_MCP_MODE
- fix(mcp): prefer repo bin launcher for Cursor in ControlKeel source tree
- fix(mcp): keep stdio stdout JSON-only for Cursor handshake

## v0.2.11 — 2026-04-15

### What's changed

- fix(mcp): skip attached-agent sync during stdio MCP startup

## v0.2.10 — 2026-04-15

### What's changed

- fix(install): scrub AGENTS.md before ControlKeel block; portable project hint

## v0.2.9 — 2026-04-15

### What's changed

- fix(mcp): Cursor stdio — workspaceFolder launcher path and CK_PROJECT_ROOT scan

## v0.2.8 — 2026-04-15

### What's changed

- chore: align Cursor plugin manifest version with app (0.2.7)
- Fix Cursor MCP stuck on Loading tools (quiet stdout for stdio MCP)

## v0.2.7 — 2026-04-15

### What's changed

- cli: use pipe separator in status and watch output

## v0.2.6 — 2026-04-15

### What's changed

- Fix Cursor bundle: priv skill precedence, portable MCP paths
- feat: enhance task verification and assurance features
- feat: add retrieval strategy configuration and support for multiple strategies in ControlKeel
- chore: update .gitignore, enhance AGENTS.md, and improve logger configuration in runtime.exs

## v0.2.5 — 2026-04-13

### What's changed

- Add Cursor plugin, fix MCP server encoding, and expand Cursor integration surface

## v0.2.4 — 2026-04-12

### What's changed

- Improve Codex install surfaces and governance docs

## v0.2.3 — 2026-04-11

### What's changed

- Expose Cloudflare runtime export in CLI
- Add skill quality diagnostics
- Add harness policy to intent boundary
- Fix init and attach project-root parsing

## v0.2.2 — 2026-04-11

### What's changed

- Expose skills as MCP resources
- Add provider trust-boundary reporting
- Add split-aware eval profiles to benchmarks
- Quiet CLI smoke output in test runs
- Add governed decomposition summaries to mission state

## v0.2.1 — 2026-04-10

### What's changed

- Add Letta Code native attach support

## v0.2.0 — 2026-04-10

### What's changed

- Add Executor runtime export support
- Add virtual bash runtime export
- Align runtime export docs and API metadata

## v0.1.43 — 2026-04-09

### What's changed

- Add JSON output mode for core CLI reads

## v0.1.42 — 2026-04-09

### What's changed

- Improve CLI proofs progress and benchmark ergonomics

## v0.1.41 — 2026-04-09

### What's changed

- Make CLI status and findings more agent ergonomic

## v0.1.40 — 2026-04-08

### What's changed

- Add derived task augmentation context

## v0.1.39 — 2026-04-08

### What's changed

- Add autonomy and improvement loop summaries

## v0.1.38 — 2026-04-08

### What's changed

- Surface security case triage summaries

## v0.1.37 — 2026-04-07

### What's changed

- Tighten security workflow proof gating

## v0.1.36 — 2026-04-07

### What's changed

- Add defensive security workflow to ControlKeel
- Add detailed ControlKeel architecture walkthrough
- Add plain-English ControlKeel explainer

## v0.1.35 — 2026-04-07

### What's changed

- Harden agent-facing validation and context resolution

## v0.1.34 — 2026-04-07

### What's changed

- Align web project-root context with CLI

## v0.1.33 — 2026-04-07

### What's changed

- Harden Codex dogfooding surfaces

## v0.1.32 — 2026-04-07

### What's changed

- Use canonical docs for wrapper aliases
- Add public host drift audit
- Make runtime recommendations availability-aware

## v0.1.31 — 2026-04-07

### What's changed

- Make typed storage explicit in execution posture

## v0.1.30 — 2026-04-07

### What's changed

- Add execution posture guidance to intent context

## v0.1.29 — 2026-04-07

### What's changed

- Ignore generated editor companion artifacts
- Harden OpenCode submit_plan execution

## v0.1.28 — 2026-04-07

### What's changed

- Improve OpenCode plan review integration
- Add .copilot/skills to project skill directories

## v0.1.27 — 2026-04-07

### What's changed

- Ignore local attach artifacts in repo
- Fix Codex self-hosting attach and install paths

## v0.1.26 — 2026-04-07

### What's changed

- Align Codex integration with native skills

## v0.1.25 — 2026-04-07

### What's changed

- Handle virtual workspace grep without ripgrep
- Clarify hosted MCP scope guidance
- Apply formatting after precommit
- Refresh integrations and export Droid plugin bundles
- Add governed MCP control-plane surfaces

## v0.1.24 — 2026-04-06

### What's changed

- Refactor research note and submission payload for clarity and accuracy
- Add research note and benchmark details for ControlKeel governance
- Add ControlKeel benchmarking artifacts and analysis scripts

## v0.1.23 — 2026-04-05

### What's changed

- feat: add Kilo Code integration with native support and enhance documentation
- feat: enhance documentation and tests for skills.sh integration and aliases

## v0.1.22 — 2026-04-05

### What's changed

- docs: update installation documentation with direct host package details and commands
- feat: introduce setup command for bootstrapping ControlKeel and enhance project root resolution

## v0.1.21 — 2026-04-05

### What's changed

- Enhance ControlKeel governance and memory management
- feat: add QA validation guide and update documentation references

## v0.1.20 — 2026-04-03

### What's changed

- Refactor documentation and code for ControlKeel integrations
- feat: add guided help system and enhance help command functionality

## v0.1.19 — 2026-04-03

### What's changed

- feat: enhance Codex CLI integration with config management and installation support

## v0.1.18 — 2026-04-03

### What's changed

- feat: add augment-native and augment-plugin support
- Add annotate and last commands for various skills in ControlKeel
- feat: add explicit review commands and enhance feedback handling in ControlKeel
- Add agent adapters and runtimes for OpenCode, Pi, and VSCode
- Add review lifecycle functionality and associated tests

## v0.1.17 — 2026-04-02

### What's changed

- docs: clarify release installs and bundle coverage

## v0.1.16 — 2026-04-01

### What's changed

- feat: add OpenCode integration support and enhance CLI configuration handling

## v0.1.15 — 2026-04-01

### What's changed

- feat: add new framework adapters and enhance security rules for leak-derived dependencies
- feat: add Socket dependency review command and related tests
- feat: enhance documentation and add security rules for SSRF and dependency hygiene

## v0.1.14 — 2026-04-01

### What's changed

- fix: improve plugin installation error handling and output messages
- docs: update attach commands and release verification checkpoints
- fix: update badge links in README for Release Smoke and Latest Release

## v0.1.13 — 2026-04-01

### What's changed

- fix: specify repository in gh run download command for artifact retrieval

## v0.1.12 — 2026-04-01

### What's changed

- feat: update workflow triggers for Release Smoke and Bump Version processes

## v0.1.11 — 2026-04-01

### What's changed

- feat: implement retry logic for finding successful Release Smoke run in release workflow

## v0.1.10 — 2026-04-01

### What's changed

- feat: rename parameter in Test-TcpPortOpen function for clarity and update references in Test-ProcessListeningPort function
- feat: enhance Test-TcpPortOpen function with null check for connectTask and improved client disposal logic
- feat: add Test-ProcessListeningPort function for enhanced server process checks in release smoke script
- feat: add Test-TcpPortOpen function for improved server connectivity checks in release smoke script
- feat: improve logging in release smoke script by separating stdout and stderr
- feat: add overwrite option to mix release commands in release smoke script
- feat: update release smoke scripts to improve server process handling and error reporting
- feat: improve error handling for daemon startup in release smoke script
- feat: enhance CI workflow, add file overwrite handling, and improve tests for deployment advisor
- feat: update CI workflow and add verification script for required patterns
- feat: remove redundant help command from release smoke script
- feat: finalize governance/docs reconciliation and quality fixes
- feat: enhance cost optimizer and outcome tracker tools with improved handling and new workspace_id defaults
- feat: add comprehensive test suite for deployment advisor, findings translation, and project governance modules
- feat: add MCP tools for cost optimization, outcome tracking, and deployment advisory with updated skill documentation
- feat: implement learning, cost management, deployment guidance, and governance modules to close system gap analysis
- feat: implement deployment advisor with automated infrastructure generation and project monitoring tools
- docs: add pathfinder gap analysis and research documentation
- docs: add documentation for mcptocli integration to agent-integrations.md
- feat: implement OWASP-style classification metrics and add benign baseline benchmark suite
- refactor: update agent support matrix to native integration and simplify README documentation
- feat: upgrade Kiro, Amp, OpenCode, and Gemini-CLI integrations to native-first mode with expanded export and installation support.
- feat: implement pluggable execution sandbox system with E2B, local, and Docker support, and add Gemini proxy capabilities
- refactor: Update documentation and remove deprecated components
- feat: Implement agent execution API and delegate tool

## v0.1.9 — 2026-03-27

### What's changed

- docs: refresh release verification and agent scope matrix
- docs: refresh Release Smoke SHA, align ck-final Mission Control, missing/ hygiene

## v0.1.8 — 2026-03-25

### What's changed

- feat: benchmark quick presets, datalist hints, ignore session exports
- docs: support matrix, check.md classification, opencode archive note
- docs: include idea/missing/check.md FAQ in version control
- feat: P1 docs, mission graph UX, validate advisory metadata, release SHAs
- feat: update .gitignore and add opencode.md for project scope and requirements

## v0.1.7 — 2026-03-24

### What's changed

- feat: complete launch-ready OpenCode onboarding and benchmark flow

## v0.1.6 — 2026-03-24

### What's changed

- feat: add ops alignment runbook and Phoenix policy template
- feat: Introduce provider brokering with ephemeral project bindings and agent auto-bootstrap capabilities.

## v0.1.5 — 2026-03-19

### What's changed

- Reduce GitHub Actions Node 20 warnings
- Record green v0.1.4 release verification

## v0.1.4 — 2026-03-19

### What's changed

- Fix Homebrew release publish and add GitHub Packages

## v0.1.3 — 2026-03-19

### What's changed

- Record latest green release smoke SHA
- Fix workflow guard expressions
- Harden release workflow triggers
- Optimize release automation workflows

## v0.1.2 — 2026-03-19

### What's changed

- Fix Windows release archive path

## v0.1.1 — 2026-03-19

### What's changed

- Implement phase 3 platform and release closure
- Revise ControlKeel status audit to reflect closed MVP gaps and remove stale claims
- Expand audit log details and clarify Phase 2 implementation gaps in the ControlKeel status document
- Update release workflows for Node 24
- Treat Burrito as release runtime for migrations
- Cancel stale release workflow runs
- Run release migrations before starting endpoint
- Fix project binding path resolution on Windows
- Fix release smoke secret and diagnostics
- Run release CLI commands synchronously
- Skip Claude auto-attach in release smoke
- Resolve release smoke binary paths
- Halt standalone release commands synchronously
- Fix Burrito standalone argv handling
- Fix Burrito standalone CLI detection
- Finish agent integration surface and fix release smoke
- Fix Zig installer in release workflows
- Fix Burrito release packaging CI
- feat: add ControlKeel skills and benchmarks for governance and compliance
- feat: enhance mission and policy training features
- feat: add skills management and governance tools
- feat(api): update task completion logic to handle string task IDs
- feat: Cursor/Windsurf attach, episodic memory, benchmark scenarios, 12 domain packs, 28 Semgrep rules
- feat: agent router (Layer 3), proof bundles, audit log, HR/Legal/Marketing policy packs
- fix: downgrade Burrito 1.5.0→1.3.0, switch Zig to 0.14.0

## v0.1.0 — 2026-03-18

First public release.

### What's included

**Core governance engine**
- Three-tier scanner: FastPath (<5ms Elixir patterns + entropy analysis) → Semgrep SAST (29 rules across 9 languages) → Advisory LLM (optional 3rd tier)
- 12 policy packs, 62 rules total: Baseline Secrets, Baseline Injection, Cost, Software, Healthcare, Finance, Education, GDPR, HR, Legal, Marketing, Sales, Real Estate
- Per-session and rolling 24h budget enforcement with warn/block decisions
- MCP server (JSON-RPC 2.0 over stdio) with five tools: `ck_validate`, `ck_context`, `ck_budget`, `ck_finding`, `ck_route`
- HTTP proxy for OpenAI and Anthropic APIs — scans both request and response content

**Agent Router (Layer 3)**
- Automatic agent selection by task type, security tier, budget, and capability
- Supports 7 agents: claude-code, cursor, codex, bolt, replit, ollama, generic-cli
- Security tier enforcement: critical tasks route only to local agents (ollama, claude-code, cursor)
- Budget-aware: falls back to free local agents (ollama) when budget is low
- Exposed via `POST /api/v1/route-agent` and the `ck_route` MCP tool

**Web UI (5 LiveViews)**
- `/start` — Mission launch wizard with domain selection, agent picker, daily budget input
- `/missions/:id` — Real-time mission control with compliance score donut, task list, approve/reject findings
- `/findings` — Cross-session findings browser with severity/status/category filters
- `/policies` — Policy Studio showing active packs, rule counts, session budgets
- `/ship` — Install-to-first-finding funnel metrics

**REST API** (`/api/v1/`) — 13 endpoints
- Sessions CRUD, task creation + update + complete (gated), content validation
- Findings with actions (approve/reject/escalate), budget summary
- Proof bundle per task (`GET /proof/:task_id`)
- Audit log per session JSON + CSV (`GET /sessions/:id/audit-log`)
- Agent routing (`POST /route-agent`)

**Task completion gate**
- `Mission.complete_task/1` blocks marking a task "done" if any open or blocked findings exist
- Returns the list of unresolved findings so the caller can surface them

**Proof Bundle**
- Structured audit artifact per task: security findings, risk score, cost, deploy readiness, compliance attestations per domain pack

**Audit Log**
- Chronological invocations + findings for a session
- JSON (default) or CSV (`?format=csv`) for export into compliance tooling

**Episodic Memory**
- `ck_context` injects `past_patterns`: top recurring blocked rules from the last 10 sessions in the same domain pack
- SQL-based implementation (no pgvector required) using SQLite GROUP BY + ORDER BY

**CLI** (11 commands)
- `init`, `attach`, `status`, `findings`, `approve`, `watch`, `mcp`, `version`, `help`
- `attach claude-code` — registers MCP server with Claude Code
- `attach cursor` — writes to `~/.config/Cursor/User/globalStorage/cursor.mcp.json`
- `attach windsurf` — writes to `~/.codeium/windsurf/mcp_config.json`
- Binary packaging via Burrito — no Erlang required on target machine

**Developer experience**
- `mix ck.smoke` — benchmark smoke check for real-world governance failure scenarios (hardcoded keys, SQL injection, client-side auth bypass, unencrypted PHI, eval() RCE, open redirect, Supabase public bucket, PII to Segment, DEBUG=True in prod, pickle.loads deserialization RCE)
- `mix ck.watch` / `controlkeel watch` — live stream of findings and budget in the terminal
- 159 tests, 0 failures

### Semgrep rules (29 across 9 languages)

**Generic**: SQL injection, XSS sinks, `dangerouslySetInnerHTML`, inline scripts, hardcoded secrets, hardcoded JWT, `eval()`, `subprocess(shell=True)`, `os.system()`, `pickle.loads()`, `curl | bash`, `rm -rf`, prototype pollution, debug mode in prod, open redirect, hardcoded credentials

**Go**: sql.Query string format, hardcoded secret, exec injection

**Rust**: unwrap in handler, unsafe block, hardcoded secret

**Java**: SQL string concatenation, hardcoded secret, XXE

**Shell**: missing `set -e`

**HCL (Terraform)**: public S3 bucket

**Dockerfile**: running as root

**Ruby**: SQL string concatenation

**PHP**: `eval()` with user input

### Policy Packs (12 packs, 62 rules)

| Pack | Rules | Key concerns |
|------|-------|-------------|
| Baseline — Secrets | 5 | AWS keys, high-entropy tokens, hardcoded credentials |
| Baseline — Injection | 4 | SQL injection, eval/exec, unsafe HTML |
| Cost | 3 | Budget overrun, cost tracking |
| Software | 6 | Debug endpoints, CORS wildcard, console.log PII |
| Healthcare | 6 | HIPAA, PHI patterns, unencrypted patient data |
| Finance | 6 | PCI DSS, plaintext card numbers |
| Education | 6 | FERPA, student data exposure |
| GDPR | 6 | PII logging, unencrypted PII fields, third-party data sharing |
| HR | 6 | Employment PII, discriminatory criteria, salary data |
| Legal | 6 | Privileged content logging, e-discovery deletion |
| Marketing | 6 | Email unsubscribe, cookie consent, PII in analytics |
| Sales | 6 | CRM PII, revenue data logging, unsolicited email |
| Real Estate | 6 | Fair Housing criteria, SSN unencrypted, tenant data |
