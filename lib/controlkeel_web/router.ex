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

  pipeline :proxy_api do
  end

  scope "/", ControlKeelWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/getting-started", PageController, :getting_started
    live "/start", OnboardingLive, :new
    live "/findings", FindingsLive, :index
    live "/ship", ShipLive, :index
    live "/missions/:id", MissionControlLive, :show
    live "/policies", PolicyStudioLive, :index
    live "/skills", SkillsLive, :index
  end

  scope "/api/v1", ControlKeelWeb do
    pipe_through :api

    get "/sessions", ApiController, :list_sessions
    post "/sessions", ApiController, :create_session
    get "/sessions/:id", ApiController, :get_session
    get "/sessions/:id/audit-log", ApiController, :audit_log
    post "/sessions/:session_id/tasks", ApiController, :create_task
    patch "/tasks/:id", ApiController, :update_task
    post "/tasks/:id/complete", ApiController, :complete_task
    post "/validate", ApiController, :validate
    get "/findings", ApiController, :list_findings
    post "/findings/:id/action", ApiController, :finding_action
    get "/budget", ApiController, :get_budget
    get "/proof/:task_id", ApiController, :proof_bundle
    post "/route-agent", ApiController, :route_agent
    get "/skills", ApiController, :list_skills
    get "/skills/:name", ApiController, :get_skill
  end

  scope "/proxy", ControlKeelWeb do
    pipe_through :proxy_api

    post "/openai/:proxy_token/v1/responses", ProxyController, :openai_responses
    post "/openai/:proxy_token/v1/chat/completions", ProxyController, :openai_chat_completions
    post "/anthropic/:proxy_token/v1/messages", ProxyController, :anthropic_messages
    get "/openai/:proxy_token/v1/realtime", ProxySocketController, :openai_realtime
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
