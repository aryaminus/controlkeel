defmodule ControlKeelWeb.Router do
  use ControlKeelWeb, :router

  pipeline :browser do
    plug ControlKeelWeb.Plugs.MarkdownNegotiation
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug ControlKeelWeb.Plugs.LoadCurrentUser
    plug ControlKeelWeb.Plugs.RequireCloudMode
    plug :put_root_layout, html: {ControlKeelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug ControlKeelWeb.Plugs.ApiAuth
  end

  pipeline :protocol_api do
    plug :accepts, ["json"]
  end

  pipeline :hosted_mcp do
    plug :accepts, ["json"]
    plug ControlKeelWeb.Plugs.ProtocolAccessAuth, resource: "mcp"
  end

  pipeline :cloud_telemetry_ingest do
    plug :accepts, ["json"]
  end

  pipeline :cloud_api_auth do
    plug ControlKeelWeb.Plugs.CloudWorkspaceKeyAuth
    plug ControlKeelWeb.Plugs.CloudRateLimit
  end

  pipeline :hosted_a2a do
    plug :accepts, ["json"]

    plug ControlKeelWeb.Plugs.ProtocolAccessAuth,
      resource: "a2a",
      include_resource_metadata: false
  end

  pipeline :require_cloud_auth do
    plug ControlKeelWeb.Plugs.RequireCloudAuth
  end

  pipeline :proxy_api do
  end

  scope "/", ControlKeelWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/getting-started", PageController, :getting_started
    get "/about", PageController, :about
    get "/contact", PageController, :contact
    get "/privacy", PageController, :privacy
    get "/developers", PageController, :developers

    # Machine-readable resources
    get "/llms.txt", LlmsTxtController, :index
    get "/sitemap.xml", SitemapController, :index

    # Public in all modes
    live "/auth/login", AuthLive, :index

    # Specific auth routes must precede parameterized OAuth routes
    # to avoid conflicts (e.g. /auth/logout matching /auth/:provider).
    get "/auth/logout", AuthController, :logout
    get "/auth/invitation/:token", AuthController, :start_invitation

    # OAuth provider sign-in (parameterized — catches /auth/google, /auth/github, etc.)
    get "/auth/:provider/request", OAuthLoginController, :request
    get "/auth/:provider/callback", OAuthLoginController, :callback

    # Public invitation-acceptance page. NOT auth-gated (acceptance requires
    # OAuth but the page itself is viewable to preview the invite).
    live_session :invitations,
      layout: {ControlKeelWeb.Layouts, :invitation} do
      live "/invitations/:token", InvitationLive, :show
    end

    # Cloud-auth gated: in cloud/self_hosted mode requires active membership.
    # In local mode the on_mount hook is a passthrough.
    live_session :cloud_auth,
      layout: {ControlKeelWeb.Layouts, :dashboard},
      on_mount: [
        {ControlKeelWeb.LiveAuth, :require_cloud_auth},
        ControlKeelWeb.LayoutDefaults
      ] do
      live "/dashboard", DashboardLive, :index
      live "/sessions", MissionsLive, :index
      live "/sessions/start", OnboardingLive, :new
      live "/sessions/:id", MissionControlLive, :show
      live "/sessions/:id/reviews", SessionReviewsLive, :index
      live "/sessions/:id/deploy-review", DeployReviewLive, :show
      live "/findings", FindingsLive, :index
      live "/benchmarks", BenchmarksLive, :index
      live "/benchmarks/runs/:id", BenchmarksLive, :show
      live "/proofs", ProofBrowserLive, :index
      live "/proofs/:id", ProofBrowserLive, :show
      live "/sessions/:sid/reviews/:rid", ReviewLive, :show
      live "/cloud/telemetry", CloudTelemetryLive, :index
      live "/cloud/projects", CloudProjectsLive, :index
      live "/cloud/projects/:ws_id", CloudProjectsLive, :show
      live "/organizations", OrganizationsLive, :index
      live "/organizations/:slug", OrganizationDetailLive, :index
      live "/organizations/:slug/workspaces/:id", WorkspaceDetailLive, :index
      live "/organizations/:slug/workspaces/:id/settings", WorkspaceSettingsLive, :show
      live "/workspaces/:id/repos", WorkspaceReposLive, :index
      live "/workspaces/:id/service-accounts", WorkspaceServiceAccountsLive, :index
      live "/workspaces/:id/webhooks", WorkspaceWebhooksLive, :index
      live "/workspaces/:id/tool-policy", WorkspaceToolPolicyLive, :edit
      live "/policies", PolicyStudioLive, :index
      live "/skills", SkillsLive, :index
    end

    # Observability section routes use the shared :dashboard framework layout;
    # each page renders its own heading. LayoutDefaults sets shared layout
    # assigns (@current_path, @page_action) for active-link highlighting.
    live_session :observability,
      layout: {ControlKeelWeb.Layouts, :dashboard},
      on_mount: [
        {ControlKeelWeb.LiveAuth, :require_cloud_auth},
        ControlKeelWeb.LayoutDefaults
      ] do
      live "/observability", ObservabilityOverviewLive, :index
      live "/observability/loop", ObservabilityLoopLive, :index
      live "/observability/benchmarks/drafts", ObservabilityBenchmarkDraftsLive, :index
      live "/observability/benchmarks/scenarios", ObservabilityBenchmarkScenariosLive, :index
      live "/observability/benchmarks/history", ObservabilityBenchmarkHistoryLive, :index
      live "/observability/compare", ObservabilityCompareLive, :index
      live "/observability/costs", ObservabilityCostsLive, :index
      live "/observability/evals", ObservabilityEvalsLive, :index
      live "/observability/imports", ObservabilityImportsLive, :index
      live "/observability/memory-quality", ObservabilityMemoryQualityLive, :index
      live "/observability/recommendations", ObservabilityRecommendationsLive, :index
      live "/observability/regressions", ObservabilityRegressionsLive, :index
      live "/observability/trends", ObservabilityTrendsLive, :index
      live "/observability/problems", ObservabilityProblemsLive, :index
      live "/observability/promotions", ObservabilityPromotionsLive, :index
    end

    # Session-scoped observability routes use the :observability_session
    # framework layout (sidebar + session tabs). LayoutDefaults sets shared
    # layout assigns (@current_path, @page_action) for tab highlighting.
    live_session :observability_session,
      layout: {ControlKeelWeb.Layouts, :observability_session},
      on_mount: [
        {ControlKeelWeb.LiveAuth, :require_cloud_auth},
        ControlKeelWeb.LayoutDefaults
      ] do
      live "/observability/sessions/:id/memory", ObservabilityMemoryLive, :show
      live "/observability/sessions/:id/timeline", ObservabilityTimelineLive, :show
      live "/observability/sessions/:id", ObservabilityLive, :show
    end
  end

  # Session export is authenticated in cloud/self_hosted (passthrough in local mode).
  scope "/", ControlKeelWeb do
    pipe_through [:browser, :require_cloud_auth]

    get "/observability/sessions/:id/export.json", ObservabilityController, :export_session
  end

  scope "/api/v1", ControlKeelWeb do
    pipe_through :api

    get "/sessions", ApiController, :list_sessions
    post "/sessions", ApiController, :create_session
    get "/sessions/:id", ApiController, :get_session
    post "/reviews", ApiController, :create_review
    get "/reviews/:id", ApiController, :get_review
    post "/reviews/:id/respond", ApiController, :respond_review
    get "/domains", ApiController, :list_domains
    get "/context", ApiController, :context
    post "/context", ApiController, :context
    get "/improvement", ApiController, :improvement_summary
    get "/sessions/:id/audit-log", ApiController, :audit_log
    get "/sessions/:id/graph", ApiController, :session_graph
    post "/sessions/:id/execute", ApiController, :execute_session
    get "/workspaces/:id/service-accounts", ApiController, :list_service_accounts
    post "/workspaces/:id/service-accounts", ApiController, :create_service_account
    get "/workspaces/:id/policy-sets", ApiController, :list_workspace_policy_sets
    post "/workspaces/:id/policy-sets", ApiController, :create_policy_set
    post "/workspaces/:id/policy-sets/:policy_set_id/apply", ApiController, :apply_policy_set
    get "/workspaces/:id/webhooks", ApiController, :list_webhooks
    post "/workspaces/:id/webhooks", ApiController, :create_webhook
    get "/workspaces/:id/tool-policy", ApiController, :get_workspace_tool_policy
    put "/workspaces/:id/tool-policy", ApiController, :set_workspace_tool_policy
    post "/service-accounts/:id/rotate", ApiController, :rotate_service_account
    delete "/service-accounts/:id", ApiController, :revoke_service_account
    get "/service-accounts/:id/events", ApiController, :list_nhi_audit_events
    post "/webhooks/:id/replay", ApiController, :replay_webhook
    get "/providers", ApiController, :list_providers
    get "/providers/status", ApiController, :provider_status
    post "/providers/default", ApiController, :set_default_provider
    post "/bootstrap", ApiController, :bootstrap_project
    post "/review/diff", ApiController, :review_diff
    post "/review/pr", ApiController, :review_pr
    post "/release/readiness", ApiController, :release_readiness
    post "/governance/install/github", ApiController, :install_github_governance
    get "/agents", ApiController, :list_agents
    post "/tasks/:id/run", ApiController, :run_task
    post "/sessions/:id/run", ApiController, :run_session
    post "/sessions/:session_id/tasks", ApiController, :create_task
    patch "/tasks/:id", ApiController, :update_task
    post "/tasks/:id/complete", ApiController, :complete_task
    post "/tasks/:id/pause", ApiController, :pause_task
    post "/tasks/:id/resume", ApiController, :resume_task
    post "/tasks/:id/claim", ApiController, :claim_task
    post "/tasks/:id/heartbeat", ApiController, :heartbeat_task
    post "/tasks/:id/checks", ApiController, :task_checks
    post "/tasks/:id/report", ApiController, :report_task
    post "/validate", ApiController, :validate
    get "/findings", API.FindingController, :list_findings
    post "/findings", API.FindingController, :create_finding
    post "/findings/:id/action", API.FindingController, :finding_action
    get "/proofs", ApiController, :list_proofs
    get "/proofs/:id", ApiController, :get_proof
    get "/benchmarks", ApiController, :list_benchmarks
    post "/benchmarks/runs", ApiController, :create_benchmark_run
    get "/benchmarks/runs/:id", ApiController, :get_benchmark_run
    get "/benchmarks/runs/:id/compare", ApiController, :compare_benchmark_run
    post "/benchmarks/runs/:id/import", ApiController, :import_benchmark_result
    get "/benchmarks/runs/:id/export", ApiController, :export_benchmark_run
    get "/budget", ApiController, :get_budget
    get "/proof/:task_id", ApiController, :proof_bundle
    get "/memory/search", ApiController, :search_memory
    post "/memory", ApiController, :create_memory
    delete "/memory/:id", ApiController, :archive_memory
    post "/route-agent", ApiController, :route_agent
    get "/skills", ApiController, :list_skills
    get "/skills/targets", ApiController, :list_skill_targets
    post "/skills/export", ApiController, :export_skills
    post "/skills/install", ApiController, :install_skills
    get "/skills/:name", ApiController, :get_skill
  end

  scope "/proxy", ControlKeelWeb do
    pipe_through :proxy_api

    post "/openai/:proxy_token/v1/responses", ProxyController, :openai_responses
    post "/openai/:proxy_token/v1/chat/completions", ProxyController, :openai_chat_completions
    post "/openai/:proxy_token/v1/completions", ProxyController, :openai_completions
    post "/openai/:proxy_token/v1/embeddings", ProxyController, :openai_embeddings
    get "/openai/:proxy_token/v1/models", ProxyController, :openai_models
    post "/anthropic/:proxy_token/v1/messages", ProxyController, :anthropic_messages
    post "/gemini/:proxy_token/v1beta/chat/completions", ProxyController, :gemini_chat_completions
    get "/gemini/:proxy_token/v1beta/openai/models", ProxyController, :gemini_models
    get "/openai/:proxy_token/v1/realtime", ProxySocketController, :openai_realtime
  end

  scope "/", ControlKeelWeb do
    pipe_through :protocol_api

    get "/.well-known/oauth-protected-resource/mcp", ProtocolController, :protected_resource_mcp
    get "/.well-known/oauth-protected-resource", ProtocolController, :protected_resource_alias
    get "/.well-known/oauth-authorization-server", ProtocolController, :authorization_server
    get "/.well-known/agent-card.json", ProtocolController, :a2a_card
    get "/.well-known/agent.json", ProtocolController, :a2a_card
    post "/oauth/token", OAuthController, :token
    get "/mcp", ProtocolController, :mcp_get
    delete "/mcp", ProtocolController, :mcp_delete
  end

  scope "/", ControlKeelWeb do
    pipe_through :hosted_mcp

    post "/mcp", ProtocolController, :mcp
  end

  scope "/", ControlKeelWeb do
    pipe_through :hosted_a2a

    post "/a2a", ProtocolController, :a2a
  end

  scope "/cloud/v1", ControlKeelWeb do
    pipe_through :cloud_telemetry_ingest

    post "/telemetry", CloudTelemetryController, :ingest
    post "/runtime/callbacks", CloudRuntimeCallbackController, :update
    post "/workspaces/register", CloudWorkspaceController, :register
  end

  scope "/cloud/v1", ControlKeelWeb do
    pipe_through [:cloud_telemetry_ingest, :cloud_api_auth]

    post "/sync/push", CloudSyncController, :push
    post "/sync/pull", CloudSyncController, :pull

    get "/orgs/:slug/usage", CloudUsageApiController, :show
  end

  if Application.compile_env(:controlkeel, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ControlKeelWeb.Telemetry
    end
  end

  # Catch-all route: returns a real 404 for any unmatched path.
  # This fixes the soft-404 issue where unknown paths returned HTTP 200
  # with the app shell, confusing AI agents into thinking every path exists.
  match :*, "/*path", ControlKeelWeb.FallbackController, :not_found
end
