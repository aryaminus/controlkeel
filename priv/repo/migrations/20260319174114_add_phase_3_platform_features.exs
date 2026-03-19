defmodule ControlKeel.Repo.Migrations.AddPhase3PlatformFeatures do
  use Ecto.Migration

  def change do
    create table(:service_accounts) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :scopes, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"
      add :last_used_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:service_accounts, [:token_hash])
    create index(:service_accounts, [:workspace_id])
    create index(:service_accounts, [:status])

    create table(:policy_sets) do
      add :name, :string, null: false
      add :scope, :string, null: false, default: "workspace"
      add :description, :string
      add :rules, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:policy_sets, [:scope])
    create index(:policy_sets, [:status])

    create table(:workspace_policy_sets) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :policy_set_id, references(:policy_sets, on_delete: :delete_all), null: false
      add :precedence, :integer, null: false, default: 100
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_policy_sets, [:workspace_id, :policy_set_id])
    create index(:workspace_policy_sets, [:workspace_id, :precedence])

    create table(:integration_webhooks) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :string, null: false
      add :secret, :string, null: false
      add :subscribed_events, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:integration_webhooks, [:workspace_id])
    create index(:integration_webhooks, [:status])

    create table(:integration_deliveries) do
      add :webhook_id, references(:integration_webhooks, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :signature, :string
      add :response_code, :integer
      add :response_body, :string
      add :attempts, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :last_attempted_at, :utc_datetime
      add :next_retry_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:integration_deliveries, [:webhook_id, :inserted_at])
    create index(:integration_deliveries, [:workspace_id, :event])
    create index(:integration_deliveries, [:status, :next_retry_at])

    create table(:task_edges) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :from_task_id, references(:tasks, on_delete: :delete_all), null: false
      add :to_task_id, references(:tasks, on_delete: :delete_all), null: false
      add :dependency_type, :string, null: false, default: "blocks"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:task_edges, [:session_id, :from_task_id, :to_task_id])
    create index(:task_edges, [:session_id])
    create index(:task_edges, [:to_task_id])

    create table(:task_runs) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :service_account_id, references(:service_accounts, on_delete: :nilify_all)
      add :status, :string, null: false, default: "ready"
      add :execution_mode, :string, null: false, default: "local"
      add :claimed_at, :utc_datetime
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :external_ref, :string
      add :output, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:task_runs, [:task_id, :inserted_at])
    create index(:task_runs, [:session_id, :status])
    create index(:task_runs, [:service_account_id, :status])

    create table(:task_check_results) do
      add :task_run_id, references(:task_runs, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :check_type, :string, null: false
      add :status, :string, null: false, default: "passed"
      add :summary, :string
      add :payload, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:task_check_results, [:task_run_id])
    create index(:task_check_results, [:task_id, :status])

    create table(:audit_exports) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :format, :string, null: false
      add :status, :string, null: false, default: "generated"
      add :checksum, :string
      add :artifact_path_or_ref, :string
      add :generated_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:audit_exports, [:session_id, :generated_at])
    create index(:audit_exports, [:format, :status])
  end
end
