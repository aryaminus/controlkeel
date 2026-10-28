defmodule ControlKeel.CLI.Dispatch.CloudSelfhost do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Accounts
  alias ControlKeel.Platform
  alias ControlKeel.Repo
  alias ControlKeel.Mcp.ProtocolAccess
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :cloud_doctor, options: _options}, _project_root) do
    report = ControlKeel.Cloud.Doctor.report()
    lines = ControlKeel.Cloud.Doctor.format(report)

    if report.ok do
      {:ok, lines}
    else
      {:error, Enum.join(lines, "\n")}
    end
  end

  def run_command(%{command: :cloud_connect, options: options}, _project_root) do
    force? = Map.get(options, :rotate, false)
    enroll_url = Map.get(options, :enroll)
    name = Map.get(options, :name)
    invite = Map.get(options, :invite)

    case ControlKeel.Cloud.Workspace.Identity.ensure(force: force?) do
      {:ok, identity, outcome} ->
        action =
          case outcome do
            :existing -> "Already connected"
            :created -> "Workspace identity created"
            :rotated -> "Workspace identity rotated"
          end

        base = [
          action,
          "Workspace ID: #{identity.workspace_id}",
          "Algorithm: #{identity.algorithm}",
          "Fingerprint: #{ControlKeel.Cloud.Workspace.Identity.short_fingerprint(identity)}...",
          "Created at: #{DateTime.to_iso8601(identity.created_at)}",
          "Identity path: #{identity.path}"
        ]

        case enroll_url do
          nil ->
            {:ok,
             base ++
               [
                 "Note: this is a local identity primitive. Pass --enroll <url> to register with a control plane."
               ]}

          url when is_binary(url) and url != "" ->
            case enroll_remote(identity, url, name: name, invite_token: invite) do
              {:ok, summary_lines} -> {:ok, base ++ summary_lines}
              {:error, reason} -> {:error, "Enrolment failed: #{reason}"}
            end
        end

      {:error, reason} ->
        {:error, "Failed to generate workspace identity: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :audit_export, options: options}, _project_root) do
    alias ControlKeel.Cloud.Audit.Export
    alias ControlKeel.Cloud.ComplianceTemplate

    with {:ok, scope_opts} <- resolve_audit_scope(options),
         {:ok, since_opt} <- parse_optional_datetime(options[:since], "since"),
         {:ok, until_opt} <- parse_optional_datetime(options[:until], "until"),
         build_opts <-
           scope_opts
           |> maybe_append(:since, since_opt)
           |> maybe_append(:until, until_opt),
         {:ok, bundle} <- Export.build(build_opts),
         {:ok, export_payload} <- maybe_render_compliance_template(bundle, options[:template]),
         {:ok, final_payload} <- maybe_sign_audit_export(export_payload, options) do
      json = Jason.encode!(final_payload, pretty: true)

      case options[:out] do
        nil ->
          {:ok, [json]}

        path ->
          case File.write(path, json) do
            :ok ->
              {:ok,
               [
                 "Audit export written",
                 "Path: #{path}",
                 "Scope: #{bundle["scope"]["type"]}/#{bundle["scope"]["id"]}",
                 "Template: #{options[:template] || "raw"}",
                 "Findings: #{length(bundle["findings"])}",
                 "Reviews: #{length(bundle["reviews"])}",
                 "MCP calls: #{length(bundle["mcp_tool_calls"])}"
               ]}

            {:error, reason} ->
              {:error, "Failed to write #{path}: #{inspect(reason)}"}
          end
      end
    else
      {:error, :scope_required} ->
        {:error, "Provide --workspace <slug> or --org <slug>"}

      {:error, :scope_conflict} ->
        {:error, "Pass exactly one of --workspace or --org"}

      {:error, :unknown_workspace} ->
        {:error, "Workspace not found"}

      {:error, :unknown_org} ->
        {:error, "Org not found"}

      {:error, {:invalid_datetime, name}} ->
        {:error, "--#{name} must be an ISO8601 timestamp (e.g. 2026-01-01T00:00:00Z)"}

      {:error, :unsupported_template} ->
        {:error,
         "--template must be one of: " <>
           Enum.join(ComplianceTemplate.supported_templates(), ", ")}

      {:error, :missing_signing_key_env} ->
        {:error, "--sign requires --signing-key-env <ENV>"}

      {:error, {:missing_signing_key, env}} ->
        {:error, "Signing key environment variable is not set: #{env}"}

      {:error, reason} ->
        {:error, "Failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :user_create, options: options}, _project_root) do
    alias ControlKeel.Accounts

    with {:ok, email} <- require_string_option(options[:email], "email") do
      attrs = %{email: email, name: options[:name]}

      case Accounts.create_user(attrs) do
        {:ok, user} ->
          {:ok,
           [
             "User created",
             "ID: #{user.id}",
             "Email: #{user.email}",
             "Name: #{user.name || "(none)"}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to create user: #{format_changeset_errors(changeset)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  # TODO(ck-cli-auth): org_create calls Accounts.create_org/1 which inserts a
  # bare org row with NO owner membership. This is intentional for now because
  # the CLI has no concept of a "current user" — there is no login/identity
  # primitive, stored credential, or session token tying the CLI to a User row.
  #
  # Consequence: CLI-created orgs are orphaned from a membership perspective.
  # After cloud migration, Accounts.list_orgs_for_user/1 will not return them,
  # and Accounts.authorize_cloud_execution/2 will reject cloud runtime work on
  # their workspaces (no membership → {:error, :unauthorized}).
  #
  # Fix: once CLI auth is introduced (e.g. `controlkeel login` storing a user
  # identity, or a --user-id/--email flag resolved to a User), this handler
  # must call Accounts.create_org_with_owner/2 instead of create_org/1 so an
  # active owner membership is created atomically with the org.
  def run_command(%{command: :org_create, options: options}, _project_root) do
    alias ControlKeel.Accounts
    alias ControlKeel.Mission

    with {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, slug} <- require_string_option(options[:slug], "slug") do
      case Accounts.create_org(%{name: name, slug: slug}) do
        {:ok, org} ->
          base_lines = [
            "Org created",
            "ID: #{org.id}",
            "Name: #{org.name}",
            "Slug: #{org.slug}",
            "Status: #{org.status}"
          ]

          case maybe_create_default_workspace(org, options) do
            {:ok, workspace} ->
              {:ok,
               base_lines ++
                 [
                   "Default workspace: #{workspace.name} (#{workspace.slug})"
                 ]}

            {:error, changeset} ->
              {:ok,
               base_lines ++
                 [
                   "Warning: failed to create default workspace: #{format_changeset_errors(changeset)}"
                 ]}

            :skip ->
              {:ok, base_lines}
          end

        {:error, changeset} ->
          {:error, "Failed to create org: #{format_changeset_errors(changeset)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :workspace_create, options: options}, _project_root) do
    alias ControlKeel.Mission

    org_slug = options[:org]

    with {:ok, org_slug} <- require_string_option(org_slug, "org"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         org when not is_nil(org) <- Accounts.get_org_by_slug(org_slug) do
      slug = options[:slug]

      case Mission.create_workspace(%{
             name: name,
             slug: slug,
             industry: "general",
             agent: "claude",
             budget_cents: 0,
             compliance_profile: "general",
             status: "active",
             org_id: org.id
           }) do
        {:ok, workspace} ->
          {:ok,
           [
             "Workspace created",
             "ID: #{workspace.id}",
             "Org: #{org.slug}",
             "Name: #{workspace.name}",
             "Slug: #{workspace.slug}",
             "Status: #{workspace.status}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to create workspace: #{format_changeset_errors(changeset)}"}
      end
    else
      {:error, {:missing_option, opt}} ->
        {:error, "Missing required option --#{opt}"}

      nil ->
        {:error, "Org not found: #{org_slug}"}
    end
  end

  def run_command(%{command: :org_list, options: _options}, _project_root) do
    alias ControlKeel.Accounts

    orgs = Accounts.list_orgs()

    if orgs == [] do
      {:ok, ["No orgs configured."]}
    else
      header = ["Orgs:"]

      rows =
        Enum.map(orgs, fn o ->
          budget = Accounts.org_budget_cents(o) || "uncapped"
          "  #{o.slug}\t#{o.name}\tbudget=#{budget}\tstatus=#{o.status}"
        end)

      {:ok, header ++ rows}
    end
  end

  def run_command(%{command: :org_budget_set, options: options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        cents =
          cond do
            Map.get(options, :clear, false) -> nil
            is_integer(options[:cents]) -> options[:cents]
            true -> :unset
          end

        case cents do
          :unset ->
            {:error, "Provide either --cents N or --clear"}

          value ->
            case Accounts.set_org_budget_cents(org.id, value) do
              {:ok, _} ->
                {:ok,
                 [
                   "Org budget updated",
                   "Org: #{org.slug}",
                   "Budget: #{value || "uncapped"}"
                 ]}

              {:error, reason} ->
                {:error, "Failed: #{inspect(reason)}"}
            end
        end
    end
  end

  def run_command(%{command: :org_budget_show, options: _options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        status = Accounts.org_budget_status(org.id)
        breakdown = Accounts.org_workspace_breakdown(org.id)

        header = [
          "Org: #{org.slug}",
          "Budget: #{status.budget_cents || "uncapped"}",
          "Spent: #{status.spent_cents}",
          "Remaining: #{status.remaining_cents || "—"}",
          "Workspaces: #{status.workspace_count}",
          "Over cap: #{status.over_cap?}"
        ]

        rows =
          case breakdown do
            [] ->
              []

            ws ->
              ["Workspace breakdown:"] ++
                Enum.map(ws, &"  #{&1.workspace_slug}\t#{&1.spent_cents}")
          end

        {:ok, header ++ rows}
    end
  end

  def run_command(%{command: :org_invite, options: options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    with {:ok, email} <- require_string_option(options[:email], "email"),
         org when not is_nil(org) <- Accounts.get_org_by_slug(slug) do
      user =
        Accounts.get_user_by_email(email) ||
          case Accounts.create_user(%{email: email}) do
            {:ok, u} -> u
            _ -> nil
          end

      cond do
        user == nil ->
          {:error, "Could not find or create user for #{email}"}

        true ->
          role = options[:role] || "member"

          case Accounts.invite_member(user.id, org.id, role: role) do
            {:ok, membership, raw_token} ->
              {:ok,
               [
                 "Invitation created",
                 "Org: #{org.slug}",
                 "User: #{user.email}",
                 "Role: #{membership.role}",
                 "Invitation token (deliver out of band): #{raw_token}"
               ]}

            {:error, changeset} ->
              {:error, "Failed to invite: #{format_changeset_errors(changeset)}"}
          end
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      nil -> {:error, "Org not found: #{slug}"}
    end
  end

  def run_command(%{command: :org_members, options: _options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        memberships = Accounts.list_memberships_for_org(org.id)

        rows =
          if memberships == [] do
            ["No members."]
          else
            Enum.map(memberships, fn m ->
              user = Accounts.get_user(m.user_id)
              email = if(user, do: user.email, else: "(deleted)")
              "  #{email}\trole=#{m.role}\tstatus=#{m.status}"
            end)
          end

        {:ok, ["Members of #{org.slug}:" | rows]}
    end
  end

  def run_command(%{command: :service_account_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         scopes = options[:scopes] || "admin",
         {:ok, %{service_account: account, token: token}} <-
           Platform.create_service_account(workspace_id, %{
             "name" => name,
             "scopes" => scopes
           }) do
      {:ok,
       [
         "Created service account ##{account.id} for workspace ##{workspace_id}.",
         "Name: #{account.name}",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}",
         "Token: #{token}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      accounts = Platform.list_service_accounts(workspace_id)

      lines =
        if accounts == [] do
          ["No service accounts found for workspace ##{workspace_id}."]
        else
          [
            "Service accounts for workspace ##{workspace_id}:"
            | Enum.map(accounts, fn account ->
                "  ##{account.id} #{account.name} [#{account.status}] client: #{ProtocolAccess.oauth_client_id(account)} scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}"
              end)
          ]
        end

      {:ok, lines}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :service_account_revoke, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, account} <- Platform.revoke_agent_identity(parsed_id) do
      {:ok, ["Revoked service account ##{account.id}. Audit event recorded."]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to revoke service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_rotate, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, %{service_account: account, token: token}} <-
           Platform.rotate_agent_identity_token(parsed_id) do
      {:ok,
       [
         "Rotated service account ##{account.id}. Audit event recorded.",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Token: #{token}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to rotate service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_set_create, options: options}, _project_root) do
    with {:ok, org_id} <- require_integer_option(options[:org_id], "org-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, rules} <- load_rules_payload(options[:rules_file]),
         {:ok, policy_set} <-
           Platform.create_policy_set(%{
             "org_id" => org_id,
             "name" => name,
             "description" => options[:description],
             "rules" => rules
           }) do
      {:ok,
       [
         "Created policy set ##{policy_set.id}.",
         "Name: #{policy_set.name}",
         "Rules: #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_set_list, options: options}, _project_root) do
    org_id = options[:org_id]

    case resolve_policy_set_org(org_id, options[:workspace_id]) do
      {:ok, org_id} ->
        workspace_id = options[:workspace_id]
        policy_sets = Platform.list_policy_sets(org_id)

        assignment_lines =
          if workspace_id do
            ["", "Assignments:"] ++
              Enum.map(Platform.list_workspace_policy_sets(workspace_id), fn assignment ->
                "  workspace ##{workspace_id} -> ##{assignment.policy_set_id} #{assignment.policy_set.name} precedence #{assignment.precedence}"
              end)
          else
            []
          end

        {:ok,
         [
           "Policy sets:"
           | Enum.map(policy_sets, fn policy_set ->
               "  ##{policy_set.id} #{policy_set.name} [#{policy_set.status}] #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))} rules"
             end)
         ] ++ assignment_lines}

      {:error, message} ->
        {:error, message}
    end
  end

  def run_command(
        %{command: :policy_set_apply, args: [workspace_id, policy_set_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_workspace_id} <- parse_id(workspace_id),
         {:ok, parsed_policy_set_id} <- parse_id(policy_set_id),
         {:ok, assignment} <-
           Platform.apply_policy_set(parsed_workspace_id, parsed_policy_set_id, %{
             "precedence" => options[:precedence] || 100,
             "enabled" => true
           }) do
      {:ok,
       [
         "Applied policy set ##{assignment.policy_set_id} to workspace ##{assignment.workspace_id}.",
         "Precedence: #{assignment.precedence}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Workspace id and policy set id must be integers."}

      {:error, reason} ->
        {:error, "Failed to apply policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, url} <- require_string_option(options[:url], "url"),
         events <- options[:events] || Enum.join(Platform.webhook_events(), ","),
         {:ok, webhook} <-
           Platform.create_webhook(workspace_id, %{
             "name" => name,
             "url" => url,
             "secret" => options[:secret],
             "subscribed_events" => events
           }) do
      {:ok,
       [
         "Created webhook ##{webhook.id} for workspace ##{workspace_id}.",
         "Events: #{Enum.join(ControlKeel.Platform.IntegrationWebhook.event_list(webhook), ", ")}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      webhooks = Platform.list_webhooks(workspace_id)
      deliveries = Platform.list_deliveries(workspace_id)

      {:ok,
       [
         "Webhooks for workspace ##{workspace_id}:"
         | Enum.map(webhooks, fn webhook ->
             "  ##{webhook.id} #{webhook.name} [#{webhook.status}] #{webhook.url}"
           end)
       ] ++
         ["", "Recent deliveries:"] ++
         Enum.map(deliveries, fn delivery ->
           "  ##{delivery.id} #{delivery.event} [#{delivery.status}] attempts #{delivery.attempts}"
         end)}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :webhook_replay, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, delivery} <- Platform.replay_webhook(parsed_id) do
      {:ok,
       [
         "Replayed webhook ##{parsed_id}.",
         "Latest delivery status: #{delivery.status}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Webhook id must be an integer."}

      {:error, :not_found} ->
        {:error, "Webhook or delivery not found."}

      {:error, reason} ->
        {:error, "Failed to replay webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :govern_bind_github, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, owner} <- require_string_option(options[:owner], "owner"),
         {:ok, repo} <- require_string_option(options[:repo], "repo") do
      opts =
        []
        |> maybe_put_kw(:default_branch, options[:default_branch])
        |> maybe_put_kw(:installation_id, options[:installation_id])

      case Mission.bind_github_repo(workspace_id, owner, repo, opts) do
        {:ok, binding} ->
          {:ok,
           [
             "Bound GitHub repository to workspace #{workspace_id}.",
             "Repo: #{binding.owner}/#{binding.repo}",
             "URL:  https://github.com/#{binding.owner}/#{binding.repo}",
             "Default branch: #{binding.default_branch || "(unset)"}",
             "Installation: #{binding.installation_id || "(unauthenticated)"}"
           ]}

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, "Failed to bind repo: #{format_changeset_errors(cs)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :govern_unbind_github, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, owner} <- require_string_option(options[:owner], "owner"),
         {:ok, repo} <- require_string_option(options[:repo], "repo") do
      case Mission.unbind_github_repo(workspace_id, owner, repo) do
        {:ok, _} ->
          {:ok, ["Unbound #{owner}/#{repo} from workspace #{workspace_id}."]}

        {:error, :not_found} ->
          {:error, "No binding found for #{owner}/#{repo} on workspace #{workspace_id}."}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :govern_list_github, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      case Mission.list_github_repos(workspace_id) do
        [] ->
          {:ok, ["No GitHub repos bound to workspace #{workspace_id}."]}

        bindings ->
          rows =
            Enum.map(bindings, fn b ->
              "  #{b.owner}/#{b.repo}#{format_default_branch(b.default_branch)}#{format_installation(b.installation_id)}"
            end)

          {:ok, ["GitHub repos bound to workspace #{workspace_id}:" | rows]}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :cloud_sync_push, options: _options}, _project_root) do
    case ControlKeel.Cloud.SyncEngine.force_sync() do
      {:ok, %{push: %{pushed: n}}} ->
        {:ok, ["Pushed #{n} record(s) to cloud."]}

      {:error, :not_configured} ->
        {:error, "Cloud sync endpoint not configured. Set cloud_sync_endpoint first."}

      {:error, :not_enrolled} ->
        {:error, "Cloud sync not configured. Run `controlkeel cloud connect` first."}

      {:error, :already_syncing} ->
        {:error, "Sync already in progress. Try again in a moment."}

      {:error, reason} ->
        {:error, "Cloud push failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :cloud_sync_pull, options: _options}, _project_root) do
    case ControlKeel.Cloud.SyncEngine.force_sync() do
      {:ok, %{pull: pull_result}} ->
        applied = Map.get(pull_result, :inserted, 0) + Map.get(pull_result, :updated, 0)
        {:ok, ["Pulled and applied #{applied} record(s) from cloud."]}

      {:error, :not_configured} ->
        {:error, "Cloud sync endpoint not configured. Set cloud_sync_endpoint first."}

      {:error, :not_enrolled} ->
        {:error, "Cloud sync not configured. Run `controlkeel cloud connect` first."}

      {:error, :already_syncing} ->
        {:error, "Sync already in progress. Try again in a moment."}

      {:error, reason} ->
        {:error, "Cloud pull failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :cloud_sync_migrate, options: _options}, _project_root) do
    {:ok,
     [
       "Cloud sync schema migrations (external_id, synced_at, lock_version) are managed by Ecto.",
       "Run `mix ecto.migrate` to apply any pending migrations.",
       "Run `mix ecto.migrations` to see current status."
     ]}
  end

  def run_command(%{command: :selfhost_pack, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    pack_opts = Enum.reject([output: options[:output]], fn {_, v} -> is_nil(v) end)

    case ControlKeel.Ops.SelfHost.pack(root, pack_opts) do
      {:ok, %{path: path, sha256: sha256}} ->
        {:ok,
         [
           "Air-gapped bundle written: #{path}",
           "SHA256: #{sha256}",
           "",
           "Ship this file to your air-gapped host. See INSTALL.md for boot instructions."
         ]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run_command(%{command: :selfhost_verify, options: _options}, _project_root) do
    result = ControlKeel.Ops.SelfHost.verify_environment()

    header = [
      "ControlKeel self-host verify",
      "Ready: #{result.ready?}",
      "Runtime mode: #{result.repo.mode}",
      "Cloud repo enabled: #{result.repo.cloud_repo_enabled?}",
      "Repo reachable: #{result.repo.repo_reachable?}#{format_repo_error(result.repo.error)}",
      "",
      "Required environment:"
    ]

    required_rows =
      Enum.map(result.required_env, fn check ->
        badge = if check.present?, do: "ok  ", else: "MISS"
        "  [#{badge}] #{check.name}#{format_value_hint(check.value_hint)}"
      end)

    recommended_rows =
      ["", "Recommended environment:"] ++
        Enum.map(result.recommended_env, fn check ->
          badge = if check.present?, do: "ok  ", else: "-   "
          "  [#{badge}] #{check.name}#{format_value_hint(check.value_hint)}"
        end)

    lines = header ++ required_rows ++ recommended_rows

    if result.ready? do
      {:ok, lines}
    else
      {:error, Enum.join(lines, "\n")}
    end
  end

  def run_command(%{command: :selfhost_manifest, options: _options}, _project_root) do
    paths = ControlKeel.Ops.SelfHost.bundle_manifest()
    {:ok, ["Air-gapped bundle manifest:"] ++ Enum.map(paths, &"  #{&1}")}
  end

  def run_command(%{command: :selfhost_install_guide, options: _options}, _project_root) do
    {:ok, [ControlKeel.Ops.SelfHost.install_guide()]}
  end

  defp maybe_create_default_workspace(org, options) do
    create? =
      case options[:default_workspace] do
        true -> true
        false -> false
        _ -> prompt_default_workspace?()
      end

    if create? do
      slug = "default-ws-" <> random_alnum(5)

      Mission.create_workspace(%{
        name: "Default Workspace",
        slug: slug,
        industry: "general",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "general",
        status: "active",
        org_id: org.id
      })
    else
      :skip
    end
  end

  defp prompt_default_workspace? do
    answer =
      IO.gets("Create a default workspace? [Y/n]: ")
      |> case do
        :eof -> ""
        {:error, _} -> ""
        input -> String.downcase(String.trim(input))
      end

    answer not in ["n", "no"]
  end

  defp random_alnum(n) do
    "abcdefghijklmnopqrstuvwxyz0123456789"
    |> String.graphemes()
    |> Enum.take_random(n)
    |> Enum.join()
  end

  # Policy sets are org-owned: listing requires an org resolved either
  # directly via --org-id or from the --workspace-id the caller passes.
  defp resolve_policy_set_org(nil, nil),
    do: {:error, "Policy sets are org-owned: pass --org-id or --workspace-id."}

  defp resolve_policy_set_org(org_id, _workspace_id) when is_integer(org_id),
    do: {:ok, org_id}

  defp resolve_policy_set_org(nil, workspace_id) when is_integer(workspace_id) do
    case Repo.get(Mission.Workspace, workspace_id) do
      nil -> {:error, "Workspace not found."}
      workspace -> {:ok, workspace.org_id}
    end
  end
end
