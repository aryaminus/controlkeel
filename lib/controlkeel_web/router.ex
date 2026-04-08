defmodule ControlKeelWeb.Router do
  use ControlKeelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
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

  pipeline :hosted_a2a do
    plug :accepts, ["json"]

    plug ControlKeelWeb.Plugs.ProtocolAccessAuth,
      resource: "a2a",
      include_resource_metadata: false
  end

  pipeline :proxy_api do
  end

  scope "/", ControlKeelWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/getting-started", PageController, :getting_started
    live "/start", OnboardingLive, :new
    live "/findings", FindingsLive, :index
    live "/benchmarks", BenchmarksLive, :index
    live "/benchmarks/runs/:id", BenchmarksLive, :show
    live "/benchmarks/policies/:id", BenchmarkPolicyLive, :show
    live "/proofs", ProofBrowserLive, :index
    live "/proofs/:id", ProofBrowserLive, :show
    live "/reviews/:id", ReviewLive, :show
    live "/ship", ShipLive, :index
    live "/missions/:id", MissionControlLive, :show
    live "/policies", PolicyStudioLive, :index
    live "/skills", SkillsLive, :index
    live "/deploy", DeploymentLive, :index
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
    post "/service-accounts/:id/rotate", ApiController, :rotate_service_account
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
    get "/findings", ApiController, :list_findings
    post "/findings/:id/action", ApiController, :finding_action
    get "/proofs", ApiController, :list_proofs
    get "/proofs/:id", ApiController, :get_proof
    get "/benchmarks", ApiController, :list_benchmarks
    post "/benchmarks/runs", ApiController, :create_benchmark_run
    get "/benchmarks/runs/:id", ApiController, :get_benchmark_run
    post "/benchmarks/runs/:id/import", ApiController, :import_benchmark_result
    get "/benchmarks/runs/:id/export", ApiController, :export_benchmark_run
    get "/policies", ApiController, :list_policies
    post "/policies/train", ApiController, :train_policy
    get "/policies/:id", ApiController, :get_policy
    post "/policies/:id/promote", ApiController, :promote_policy
    post "/policies/:id/archive", ApiController, :archive_policy
    get "/budget", ApiController, :get_budget
    get "/proof/:task_id", ApiController, :proof_bundle
    get "/memory/search", ApiController, :search_memory
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

  if Application.compile_env(:controlkeel, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ControlKeelWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
