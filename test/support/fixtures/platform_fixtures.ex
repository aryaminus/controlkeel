defmodule ControlKeel.PlatformFixtures do
  @moduledoc false

  alias ControlKeel.Platform

  def service_account_fixture(attrs \\ %{}) do
    workspace_id = Map.fetch!(attrs, :workspace_id)

    {:ok, %{service_account: account, token: token}} =
      Platform.create_service_account(
        workspace_id,
        %{
          "name" => Map.get(attrs, :name, "worker"),
          "scopes" => Map.get(attrs, :scopes, "admin"),
          "metadata" => Map.get(attrs, :metadata, %{})
        }
      )

    %{service_account: account, token: token}
  end

  def policy_set_fixture(attrs \\ %{}) do
    {:ok, policy_set} =
      Platform.create_policy_set(%{
        "name" => Map.get(attrs, :name, "Workspace Guard"),
        "scope" => Map.get(attrs, :scope, "workspace"),
        "description" => Map.get(attrs, :description, "Workspace-specific controls"),
        "rules" =>
          Map.get(attrs, :rules, [
            %{
              "id" => "workspace.no_payroll_exports",
              "category" => "compliance",
              "severity" => "high",
              "action" => "block",
              "plain_message" => "Payroll exports require explicit human approval.",
              "matcher" => %{"type" => "regex", "patterns" => ["PAYROLL_EXPORT"]}
            }
          ])
      })

    policy_set
  end

  def webhook_fixture(attrs \\ %{}) do
    workspace_id = Map.fetch!(attrs, :workspace_id)

    {:ok, webhook} =
      Platform.create_webhook(workspace_id, %{
        "name" => Map.get(attrs, :name, "CI Webhook"),
        "url" => Map.get(attrs, :url, "http://localhost:9999/hooks"),
        "secret" => Map.get(attrs, :secret, "secret"),
        "subscribed_events" => Map.get(attrs, :subscribed_events, "task.completed")
      })

    webhook
  end
end
