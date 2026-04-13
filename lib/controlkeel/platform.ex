defmodule ControlKeel.Platform do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.{AuditExports, Bus, Mission, Repo}
  alias ControlKeel.Mission.Decomposition
  alias ControlKeel.Mission.{ProofBundle, Session, Task}

  alias ControlKeel.Platform.{
    AuditExport,
    IntegrationDelivery,
    IntegrationWebhook,
    PolicySet,
    ServiceAccount,
    TaskCheckResult,
    TaskEdge,
    TaskGraph,
    TaskRun,
    WorkspacePolicySet
  }

  alias ControlKeel.Policy.Rule

  @webhook_events [
    "task.ready",
    "task.started",
    "task.waiting_callback",
    "task.completed",
    "task.failed",
    "finding.created",
    "finding.approved",
    "finding.rejected",
    "proof.generated",
    "audit.exported"
  ]
  @retry_backoff_ms [0, 100, 250]

  def webhook_events, do: @webhook_events

  def list_service_accounts(workspace_id) do
    ServiceAccount
    |> where([account], account.workspace_id == ^workspace_id)
    |> order_by([account], asc: account.name, asc: account.id)
    |> Repo.all()
  end

  def get_service_account(id), do: Repo.get(ServiceAccount, id)

  def create_service_account(workspace_id, attrs) do
    token = generate_token()

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("workspace_id", workspace_id)
      |> Map.put("token_hash", token_hash(token))
      |> Map.put_new("status", "active")
      |> Map.put_new("metadata", %{})

    with {:ok, account} <- %ServiceAccount{} |> ServiceAccount.changeset(attrs) |> Repo.insert() do
      {:ok, %{service_account: account, token: token}}
    end
  end

  def revoke_service_account(id) when is_integer(id) do
    case Repo.get(ServiceAccount, id) do
      nil -> {:error, :not_found}
      account -> account |> ServiceAccount.changeset(%{status: "revoked"}) |> Repo.update()
    end
  end

  def rotate_service_account(id) when is_integer(id) do
    case Repo.get(ServiceAccount, id) do
      nil ->
        {:error, :not_found}

      account ->
        token = generate_token()

        attrs = %{
          token_hash: token_hash(token),
          last_used_at: nil,
          status: "active"
        }

        with {:ok, updated} <- account |> ServiceAccount.changeset(attrs) |> Repo.update() do
          {:ok, %{service_account: updated, token: token}}
        end
    end
  end

  def authenticate_service_account(token) when is_binary(token) do
    case Repo.get_by(ServiceAccount, token_hash: token_hash(token), status: "active") do
      nil ->
        {:error, :unauthorized}

      account ->
        {:ok, _updated} =
          account
          |> ServiceAccount.changeset(%{
            last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()

        {:ok, Repo.preload(account, :workspace)}
    end
  end

  def service_account_has_scope?(%ServiceAccount{} = account, required_scopes) do
    scopes = MapSet.new(ServiceAccount.scope_list(account))

    required_scopes
    |> List.wrap()
    |> Enum.any?(fn required ->
      required in ["*", "admin"] or MapSet.member?(scopes, required) or
        MapSet.member?(scopes, "admin")
    end)
  end

  def list_policy_sets(opts \\ %{}) do
    scope = Map.get(opts, :scope) || Map.get(opts, "scope")

    PolicySet
    |> maybe_filter(:scope, scope)
    |> order_by([policy_set], asc: policy_set.name, asc: policy_set.id)
    |> Repo.all()
  end

  def get_policy_set(id), do: Repo.get(PolicySet, id)

  def create_policy_set(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("status", "active")
      |> Map.put_new("metadata", %{})

    %PolicySet{}
    |> PolicySet.changeset(attrs)
    |> Repo.insert()
  end

  def list_workspace_policy_sets(workspace_id) do
    WorkspacePolicySet
    |> where(
      [assignment],
      assignment.workspace_id == ^workspace_id and assignment.enabled == true
    )
    |> order_by([assignment], asc: assignment.precedence, asc: assignment.id)
    |> preload(:policy_set)
    |> Repo.all()
  end

  def apply_policy_set(workspace_id, policy_set_id, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("workspace_id", workspace_id)
      |> Map.put("policy_set_id", policy_set_id)
      |> Map.put_new("enabled", true)

    %WorkspacePolicySet{}
    |> WorkspacePolicySet.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [precedence: attrs["precedence"] || 100, enabled: attrs["enabled"]]],
      conflict_target: [:workspace_id, :policy_set_id]
    )
  end

  def workspace_policy_rules(workspace_id) when is_integer(workspace_id) do
    workspace_id
    |> list_workspace_policy_sets()
    |> Enum.flat_map(fn assignment -> PolicySet.rule_entries(assignment.policy_set) end)
    |> Enum.flat_map(&decode_rule/1)
  end

  def session_policy_rules(session_id) do
    case Mission.get_session(session_id) do
      %Session{workspace_id: workspace_id} -> workspace_policy_rules(workspace_id)
      _ -> []
    end
  end

  def list_webhooks(workspace_id) do
    IntegrationWebhook
    |> where([webhook], webhook.workspace_id == ^workspace_id)
    |> order_by([webhook], asc: webhook.name, asc: webhook.id)
    |> Repo.all()
  end

  def get_webhook(id), do: Repo.get(IntegrationWebhook, id)

  def create_webhook(workspace_id, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("workspace_id", workspace_id)
      |> Map.put_new("status", "active")
      |> Map.put_new("metadata", %{})
      |> Map.put_new_lazy("secret", &generate_token/0)

    %IntegrationWebhook{}
    |> IntegrationWebhook.changeset(attrs)
    |> Repo.insert()
  end

  def list_deliveries(workspace_id) do
    IntegrationDelivery
    |> where([delivery], delivery.workspace_id == ^workspace_id)
    |> order_by([delivery], desc: delivery.inserted_at, desc: delivery.id)
    |> preload(:webhook)
    |> Repo.all()
  end

  def replay_delivery(id) when is_integer(id) do
    case IntegrationDelivery |> Repo.get(id) |> Repo.preload(:webhook) do
      nil ->
        {:error, :not_found}

      delivery ->
        run_delivery(delivery)
    end
  end

  def replay_webhook(id) when is_integer(id) do
    IntegrationDelivery
    |> where([delivery], delivery.webhook_id == ^id)
    |> order_by([delivery], desc: delivery.inserted_at, desc: delivery.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      delivery -> replay_delivery(delivery.id)
    end
  end

  def emit_event(event, payload, opts \\ []) when is_binary(event) and is_map(payload) do
    workspace_id =
      opts[:workspace_id] ||
        payload["workspace_id"] ||
        payload[:workspace_id]

    async? = Keyword.get(opts, :async, true)

    if workspace_id do
      active_webhooks_for_event(workspace_id, event)
      |> Enum.each(fn webhook ->
        {:ok, delivery} =
          %IntegrationDelivery{}
          |> IntegrationDelivery.changeset(%{
            webhook_id: webhook.id,
            workspace_id: webhook.workspace_id,
            event: event,
            payload: stringify_keys(payload),
            status: "pending",
            metadata: %{}
          })
          |> Repo.insert()

        if async? do
          Elixir.Task.start(fn -> run_delivery(delivery.id) end)
        else
          _ = run_delivery(delivery.id)
        end
      end)
    end

    _ = Bus.publish_json("controlkeel.events.#{event}", stringify_keys(payload))
    :ok
  end

  def ensure_session_graph(session_id) do
    tasks = list_session_tasks(session_id)
    existing_edges = list_task_edges(session_id)

    if tasks != [] and existing_edges == [] do
      TaskGraph.build_edges(tasks)
      |> Enum.each(fn attrs ->
        %TaskEdge{}
        |> TaskEdge.changeset(attrs)
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:session_id, :from_task_id, :to_task_id]
        )
      end)
    end

    graph(session_id)
  end

  def list_task_edges(session_id) do
    TaskEdge
    |> where([edge], edge.session_id == ^session_id)
    |> order_by([edge], asc: edge.id)
    |> Repo.all()
  end

  def list_task_runs(opts \\ %{}) do
    session_id = Map.get(opts, :session_id) || Map.get(opts, "session_id")
    task_id = Map.get(opts, :task_id) || Map.get(opts, "task_id")

    TaskRun
    |> maybe_filter(:session_id, session_id)
    |> maybe_filter(:task_id, task_id)
    |> order_by([run], asc: run.id)
    |> preload([:service_account, :check_results])
    |> Repo.all()
  end

  def graph(session_id) do
    tasks = list_session_tasks(session_id)
    edges = list_task_edges(session_id)
    ready_ids = TaskGraph.ready_task_ids(tasks, edges)
    incoming = Enum.group_by(edges, & &1.to_task_id)
    outgoing = Enum.group_by(edges, & &1.from_task_id)

    %{
      session_id: session_id,
      tasks:
        Enum.map(tasks, fn task ->
          %{
            id: task.id,
            title: task.title,
            status: task.status,
            position: task.position,
            incoming_count: length(Map.get(incoming, task.id, [])),
            outgoing_count: length(Map.get(outgoing, task.id, [])),
            decomposition: Decomposition.task_summary(task, tasks, edges)
          }
        end),
      edges:
        Enum.map(edges, fn edge ->
          %{
            id: edge.id,
            from_task_id: edge.from_task_id,
            to_task_id: edge.to_task_id,
            dependency_type: edge.dependency_type,
            decomposition: Decomposition.edge_summary(edge, tasks)
          }
        end),
      decomposition: Decomposition.session_summary(tasks, edges),
      ready_task_ids: ready_ids,
      task_runs: Enum.map(list_task_runs(%{session_id: session_id}), &task_run_summary/1)
    }
  end

  def execute_session(session_id, opts \\ %{}) do
    _ = ensure_session_graph(session_id)
    tasks = list_session_tasks(session_id)
    edges = list_task_edges(session_id)
    ready_ids = TaskGraph.ready_task_ids(tasks, edges)
    execution_mode = Map.get(opts, "execution_mode", Map.get(opts, :execution_mode, "local"))

    tasks
    |> Enum.filter(&(&1.id in ready_ids and &1.status == "queued"))
    |> Enum.each(fn task ->
      {:ok, _task} = Mission.update_task(task, %{status: "ready"})
    end)

    ready_ids
    |> Enum.map(&Mission.get_task/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn task ->
      if is_nil(active_task_run(task.id)) do
        {:ok, _run} =
          %TaskRun{}
          |> TaskRun.changeset(%{
            task_id: task.id,
            session_id: task.session_id,
            status: "ready",
            execution_mode: execution_mode,
            output: %{},
            metadata: %{}
          })
          |> Repo.insert()

        emit_event("task.ready", task_event_payload(task),
          workspace_id: workspace_id_for_task(task)
        )
      end
    end)

    {:ok, graph(session_id)}
  end

  def claim_task(task_id, service_account \\ nil, attrs \\ %{}) do
    with %Task{} = task <- Mission.get_task(task_id),
         true <- task.status in ["ready", "queued", "in_progress"] || {:error, :invalid_status} do
      run = active_task_run(task.id)

      attrs =
        attrs
        |> stringify_keys()
        |> Map.put_new("execution_mode", execution_mode_for(service_account))
        |> Map.put_new("metadata", %{})
        |> Map.put_new("output", %{})
        |> Map.put("claimed_at", now())
        |> Map.put("started_at", now())
        |> Map.put("status", "in_progress")
        |> Map.put("task_id", task.id)
        |> Map.put("session_id", task.session_id)
        |> maybe_put_service_account(service_account)

      result =
        if run do
          run |> TaskRun.changeset(attrs) |> Repo.update()
        else
          %TaskRun{} |> TaskRun.changeset(attrs) |> Repo.insert()
        end

      with {:ok, task_run} <- result,
           {:ok, task} <- Mission.update_task(task, %{status: "in_progress"}) do
        emit_event("task.started", task_event_payload(task),
          workspace_id: workspace_id_for_task(task)
        )

        {:ok, Repo.preload(task_run, [:service_account, :check_results])}
      end
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
      false -> {:error, :invalid_status}
    end
  end

  def heartbeat_task(task_id, service_account \\ nil, attrs \\ %{}) do
    with %TaskRun{} = run <- active_task_run(task_id) do
      metadata =
        run.metadata
        |> Kernel.||(%{})
        |> Map.merge(%{
          "last_heartbeat_at" => DateTime.to_iso8601(now()),
          "progress" => Map.get(attrs, "progress", Map.get(attrs, :progress)),
          "note" => Map.get(attrs, "note", Map.get(attrs, :note))
        })

      attrs =
        %{
          metadata: metadata
        }
        |> maybe_put_service_account(service_account)

      run |> TaskRun.changeset(attrs) |> Repo.update()
    else
      nil -> {:error, :not_found}
    end
  end

  def record_task_checks(task_id, service_account \\ nil, checks) when is_list(checks) do
    with %Task{} = task <- Mission.get_task(task_id),
         %TaskRun{} = run <- active_task_run(task_id) do
      checks
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {check, index}, multi ->
        Multi.insert(multi, {:check, index}, fn _changes ->
          %TaskCheckResult{}
          |> TaskCheckResult.changeset(%{
            task_run_id: run.id,
            task_id: task.id,
            session_id: task.session_id,
            check_type: Map.get(check, "check_type", Map.get(check, :check_type, "external")),
            status: Map.get(check, "status", Map.get(check, :status, "passed")),
            summary: Map.get(check, "summary", Map.get(check, :summary)),
            payload: Map.get(check, "payload", Map.get(check, :payload, %{})),
            metadata: Map.get(check, "metadata", Map.get(check, :metadata, %{}))
          })
        end)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, inserted} ->
          _ = service_account
          {:ok, Map.values(inserted)}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def report_task(task_id, service_account \\ nil, attrs) do
    requested_status = Map.get(attrs, "status", Map.get(attrs, :status, "done"))

    with %Task{} = task <- Mission.get_task(task_id),
         %TaskRun{} = run <- active_task_run(task_id) do
      output = Map.get(attrs, "output", Map.get(attrs, :output, %{}))
      metadata = Map.get(attrs, "metadata", Map.get(attrs, :metadata, %{}))

      run_attrs =
        %{
          output: output,
          metadata: Map.merge(run.metadata || %{}, stringify_keys(metadata)),
          finished_at:
            if(requested_status in ["done", "failed", "blocked", "paused"], do: now(), else: nil),
          status: requested_status
        }
        |> maybe_put_service_account(service_account)

      with {:ok, updated_run} <- run |> TaskRun.changeset(run_attrs) |> Repo.update(),
           {:ok, task} <- apply_task_report(task, requested_status, output, metadata) do
        emit_report_event(task.status, task)
        maybe_release_downstream(task.session_id)
        {:ok, Repo.preload(updated_run, [:service_account, :check_results])}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def export_audit_log(session_id, format) when format in ["json", "csv", "pdf"] do
    with %Session{} = session <- Mission.get_session_context(session_id),
         {:ok, audit_log} <- Mission.audit_log(session_id),
         graph <- ensure_session_graph(session_id),
         proofs <- session_proofs(session_id),
         {:ok, payload, metadata} <-
           AuditExports.render(session, audit_log, graph, proofs, format),
         {:ok, export} <- persist_audit_export(session_id, format, metadata) do
      emit_event(
        "audit.exported",
        %{
          "workspace_id" => session.workspace_id,
          "session_id" => session.id,
          "audit_export_id" => export.id,
          "format" => format,
          "checksum" => export.checksum
        },
        workspace_id: session.workspace_id
      )

      {:ok, %{export: export, payload: payload}}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def persist_proof_generated(%ProofBundle{} = proof) do
    session = Mission.get_session(proof.session_id)

    emit_event(
      "proof.generated",
      %{
        "workspace_id" => session && session.workspace_id,
        "session_id" => proof.session_id,
        "task_id" => proof.task_id,
        "proof_id" => proof.id,
        "deploy_ready" => proof.deploy_ready
      },
      workspace_id: session && session.workspace_id
    )
  end

  defp run_delivery(id) when is_integer(id) do
    case IntegrationDelivery |> Repo.get(id) |> Repo.preload(:webhook) do
      nil -> {:error, :not_found}
      delivery -> run_delivery(delivery)
    end
  end

  defp run_delivery(%IntegrationDelivery{} = delivery) do
    body = Jason.encode!(delivery.payload)
    signature = sign_payload(body, delivery.webhook.secret)

    result =
      Enum.reduce_while(@retry_backoff_ms, {:error, :unreachable}, fn backoff_ms, _acc ->
        if backoff_ms > 0 do
          Process.sleep(backoff_ms)
        end

        case Req.post(
               url: delivery.webhook.url,
               body: body,
               headers: [
                 {"content-type", "application/json"},
                 {"user-agent", "ControlKeel/#{Application.spec(:controlkeel, :vsn) || "0.2.0"}"},
                 {"x-controlkeel-event", delivery.event},
                 {"x-controlkeel-signature", signature}
               ],
               receive_timeout: 5_000
             ) do
          {:ok, response} ->
            {:halt, {:ok, response}}

          {:error, reason} ->
            {:cont, {:error, reason}}
        end
      end)

    attrs =
      case result do
        {:ok, response} ->
          %{
            signature: signature,
            response_code: response.status,
            response_body: response.body |> to_string() |> String.slice(0, 1_000),
            attempts: delivery.attempts + length(@retry_backoff_ms),
            status: "delivered",
            last_attempted_at: now(),
            next_retry_at: nil
          }

        {:error, reason} ->
          %{
            signature: signature,
            response_body: inspect(reason),
            attempts: delivery.attempts + length(@retry_backoff_ms),
            status: "failed",
            last_attempted_at: now(),
            next_retry_at: DateTime.add(now(), 300, :second)
          }
      end

    delivery
    |> IntegrationDelivery.changeset(attrs)
    |> Repo.update()
  end

  defp persist_audit_export(session_id, format, metadata) do
    %AuditExport{}
    |> AuditExport.changeset(%{
      session_id: session_id,
      format: format,
      status: "generated",
      checksum: metadata.checksum,
      artifact_path_or_ref: metadata.artifact_path_or_ref,
      generated_at: metadata.generated_at,
      metadata: %{}
    })
    |> Repo.insert()
  end

  defp active_webhooks_for_event(workspace_id, event) do
    list_webhooks(workspace_id)
    |> Enum.filter(fn webhook ->
      webhook.status == "active" and event in IntegrationWebhook.event_list(webhook)
    end)
  end

  defp task_run_summary(run) do
    %{
      id: run.id,
      task_id: run.task_id,
      status: run.status,
      execution_mode: run.execution_mode,
      external_ref: run.external_ref,
      check_results:
        Enum.map(
          run.check_results || [],
          &%{id: &1.id, check_type: &1.check_type, status: &1.status}
        )
    }
  end

  defp task_event_payload(task) do
    %{
      "workspace_id" => workspace_id_for_task(task),
      "session_id" => task.session_id,
      "task_id" => task.id,
      "title" => task.title,
      "status" => task.status,
      "validation_gate" => task.validation_gate
    }
  end

  defp workspace_id_for_task(task) do
    case Mission.get_session(task.session_id) do
      nil -> nil
      session -> session.workspace_id
    end
  end

  defp execution_mode_for(%ServiceAccount{}), do: "external"
  defp execution_mode_for(_other), do: "local"

  defp active_task_run(task_id) do
    TaskRun
    |> where([run], run.task_id == ^task_id and run.status not in ["done", "failed"])
    |> order_by([run], desc: run.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      run -> Repo.preload(run, [:service_account, :check_results])
    end
  end

  defp apply_task_report(task, "done", output, metadata) do
    with {:ok, updated_task} <-
           Mission.update_task(task, %{
             metadata: Map.merge(task.metadata || %{}, stringify_keys(metadata))
           }),
         {:ok, done_task} <- Mission.complete_task(updated_task.id) do
      _ = output
      {:ok, done_task}
    else
      {:error, :unresolved_findings, findings} ->
        {:ok, blocked_task} = Mission.update_task(task, %{status: "blocked"})
        {:error, {:unresolved_findings, findings, blocked_task}}

      other ->
        other
    end
  end

  defp apply_task_report(task, status, output, metadata)
       when status in ["failed", "waiting_callback", "paused", "blocked"] do
    _ = output

    Mission.update_task(task, %{
      status: status,
      metadata: Map.merge(task.metadata || %{}, stringify_keys(metadata))
    })
  end

  defp apply_task_report(_task, _status, _output, _metadata), do: {:error, :invalid_status}

  defp emit_report_event("done", task),
    do:
      emit_event("task.completed", task_event_payload(task),
        workspace_id: workspace_id_for_task(task)
      )

  defp emit_report_event("verified", task) do
    :ok =
      emit_event("task.completed", task_event_payload(task),
        workspace_id: workspace_id_for_task(task)
      )

    emit_event("task.verified", task_event_payload(task),
      workspace_id: workspace_id_for_task(task)
    )
  end

  defp emit_report_event("waiting_callback", task),
    do:
      emit_event("task.waiting_callback", task_event_payload(task),
        workspace_id: workspace_id_for_task(task)
      )

  defp emit_report_event("failed", task),
    do:
      emit_event("task.failed", task_event_payload(task),
        workspace_id: workspace_id_for_task(task)
      )

  defp emit_report_event(_status, _task), do: :ok

  defp maybe_release_downstream(session_id) do
    _ = execute_session(session_id)
    :ok
  end

  defp list_session_tasks(session_id) do
    Task
    |> where([task], task.session_id == ^session_id)
    |> order_by([task], asc: task.position, asc: task.id)
    |> Repo.all()
  end

  defp session_proofs(session_id) do
    ProofBundle
    |> where([proof], proof.session_id == ^session_id)
    |> order_by([proof], asc: proof.task_id, desc: proof.version)
    |> preload(:task)
    |> Repo.all()
    |> Enum.group_by(& &1.task_id)
    |> Enum.map(fn {_task_id, [proof | _rest]} -> proof end)
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp sign_payload(body, secret) do
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), normalize_value(value)} end)
  end

  defp normalize_value(value) when is_map(value), do: stringify_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp maybe_put_service_account(attrs, %ServiceAccount{} = account),
    do: Map.put(attrs, "service_account_id", account.id)

  defp maybe_put_service_account(attrs, _other), do: attrs

  defp token_hash(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp decode_rule(raw_rule) do
    case raw_rule do
      %{
        "id" => id,
        "category" => category,
        "severity" => severity,
        "action" => action,
        "plain_message" => plain_message,
        "matcher" => matcher
      }
      when is_map(matcher) and action in ["warn", "block", "escalate_to_human"] ->
        [
          %Rule{
            id: id,
            category: category,
            severity: severity,
            action: action,
            plain_message: plain_message,
            matcher: matcher
          }
        ]

      _other ->
        []
    end
  end
end
