defmodule ControlKeel.Scanner.FastPathTest do
  use ControlKeel.DataCase

  alias ControlKeel.Scanner.FastPath

  import ControlKeel.MissionFixtures

  test "loads domain-specific rules when domain_pack is provided directly" do
    result =
      FastPath.scan(%{
        "content" => "def score(candidate), do: reject(candidate.age > 50)",
        "path" => "lib/hr/ranker.ex",
        "kind" => "code",
        "domain_pack" => "hr"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "hr.discriminatory_criteria"))
    assert result.decision == "block"
  end

  test "loads domain-specific rules from the governed session context" do
    session = session_fixture(%{execution_brief: %{"domain_pack" => "legal"}})

    result =
      FastPath.scan(%{
        "content" => ~S|Logger.info("privileged memo=#{matter.privileged_memo}")|,
        "path" => "lib/legal/audit.ex",
        "kind" => "code",
        "session_id" => session.id
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "legal.privileged_content_logging"))
    assert result.decision == "block"
  end

  test "baseline rules still apply alongside domain-specific rules" do
    result =
      FastPath.scan(%{
        "content" => ~s(export CRM_KEY="AKIAIOSFODNN7EXAMPLE"),
        "path" => "scripts/setup.sh",
        "kind" => "shell",
        "domain_pack" => "sales"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "secret.aws_access_key"))
    assert result.decision == "block"
  end

  test "loads new government domain rules when the pack is selected" do
    result =
      FastPath.scan(%{
        "content" => "Repo.query!(\"DELETE FROM permit_records WHERE inserted_at < NOW()\")",
        "path" => "lib/gov/records_cleanup.ex",
        "kind" => "code",
        "domain_pack" => "government"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "government.records_retention_bypass"))
    assert result.decision == "block"
  end

  test "loads new ecommerce domain rules when the pack is selected" do
    result =
      FastPath.scan(%{
        "content" => ~S|Logger.info("card_number=#{order.card_number} cvv=#{order.cvv}")|,
        "path" => "lib/shop/checkout_logger.ex",
        "kind" => "code",
        "domain_pack" => "ecommerce"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "ecommerce.payment_logging"))
    assert result.decision == "block"
  end

  test "blocks destructive repo-wide shell cleanup commands with recovery guidance" do
    result =
      FastPath.scan(%{
        "content" => "git checkout -- . && git clean -fd",
        "path" => "scripts/cleanup.sh",
        "kind" => "shell"
      })

    assert result.decision == "block"

    assert Enum.any?(
             result.findings,
             &(&1.rule_id == "destructive.shell.git_checkout_repo_wide")
           )

    clean_finding =
      Enum.find(result.findings, &(&1.rule_id == "destructive.shell.git_clean_force"))

    assert clean_finding
    assert clean_finding.category == "destructive_operation"
    assert clean_finding.metadata["checkpoint_recommended"] == true
    assert is_binary(clean_finding.metadata["recovery_guidance"])
  end

  test "does not flag path-scoped git restore commands as repo-wide destructive cleanup" do
    result =
      FastPath.scan(%{
        "content" => "git restore lib/controlkeel/scanner/fast_path.ex",
        "path" => "scripts/recover.sh",
        "kind" => "shell"
      })

    refute Enum.any?(result.findings, &String.starts_with?(&1.rule_id, "destructive.shell."))
  end

  test "catches SECRET_KEY assignment pattern (debug_mode_production fix)" do
    result =
      FastPath.scan(%{
        "content" => ~s(SECRET_KEY = "django-insecure-abc123xyz456"),
        "path" => "config/settings.py",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "secret.hardcoded_credential"))
    assert result.decision == "block"
  end

  test "catches Elixir module attribute hardcoded credential (hardcoded_admin_role fix)" do
    result =
      FastPath.scan(%{
        "content" => ~s(@master_password "changeme123"),
        "path" => "lib/admin/auth.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "secret.hardcoded_credential"))
    assert result.decision == "block"
  end

  test "catches SQL built with Elixir <> string concatenation (supabase_storage_public_bucket fix)" do
    result =
      FastPath.scan(%{
        "content" =>
          ~s(query = "SELECT * FROM storage.objects WHERE bucket_id = '" <> bucket_id <> "'"),
        "path" => "lib/storage/query.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.sql_injection"))
    assert result.decision == "block"
  end

  test "catches SQL built with || concatenation (sql_injection extended)" do
    result =
      FastPath.scan(%{
        "content" => ~s(query = "SELECT * FROM users WHERE id = " || user_id),
        "path" => "lib/users/query.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.sql_injection"))
    assert result.decision == "block"
  end

  test "catches user-controlled redirect (open_redirect)" do
    result =
      FastPath.scan(%{
        "content" => ~s|redirect(conn, to: params["return_url"])|,
        "path" => "lib/web/auth_controller.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.open_redirect"))
    assert result.decision == "block"
  end

  test "catches pickle deserialization (pickle_deserialization_rce)" do
    result =
      FastPath.scan(%{
        "content" => "data = pickle.loads(request.body)",
        "path" => "app/handlers.py",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.unsafe_deserialization"))
    assert result.decision == "block"
  end

  test "catches JWT none algorithm (jwt_none_algorithm)" do
    result =
      FastPath.scan(%{
        "content" => ~s|token = JWT.decode(header, algorithm: "none")|,
        "path" => "lib/auth/token.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.jwt_none_algorithm"))
    assert result.decision == "block"
  end

  test "catches JWT alg:none in JSON header (jwt_none_algorithm json)" do
    result =
      FastPath.scan(%{
        "content" => ~s(header = %{"alg" => "none", "typ" => "JWT"}),
        "path" => "lib/auth/jwt.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.jwt_none_algorithm"))
    assert result.decision == "block"
  end

  test "catches plaintext password field in Ecto schema (plaintext_password_storage)" do
    result =
      FastPath.scan(%{
        "content" => "field :password, :string",
        "path" => "lib/accounts/user.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.plaintext_password_storage"))
    assert result.decision == "block"
  end

  test "catches Plug.Upload usage (file_upload_no_validation)" do
    result =
      FastPath.scan(%{
        "content" => "%Plug.Upload{path: tmp_path, filename: filename} = upload",
        "path" => "lib/web/upload_controller.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.file_upload_no_validation"))
  end

  test "catches all-env dump via System.get_env() (env_dump_leak)" do
    result =
      FastPath.scan(%{
        "content" => "all_config = System.get_env()",
        "path" => "lib/debug/env.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.env_dump_leak"))
    assert result.decision == "block"
  end

  test "does not flag patient_data function parameter (healthcare phi_marker FP fix)" do
    result =
      FastPath.scan(%{
        "content" => "def process(patient_data, patient_id), do: encrypt(patient_data)",
        "path" => "lib/health/processor.ex",
        "kind" => "code",
        "domain_pack" => "healthcare"
      })

    refute Enum.any?(result.findings, &(&1.rule_id == "healthcare.phi_marker"))
  end

  test "does not flag console.log with user variable (console_log_sensitive FP fix)" do
    result =
      FastPath.scan(%{
        "content" => ~s|console.log('Processing for user:', user.id)|,
        "path" => "src/handlers.js",
        "kind" => "code",
        "domain_pack" => "software"
      })

    refute Enum.any?(result.findings, &(&1.rule_id == "software.console_log_sensitive"))
  end

  test "catches Elixir put_resp_header CORS wildcard (cors_wildcard fix)" do
    result =
      FastPath.scan(%{
        "content" => ~s|put_resp_header(conn, "access-control-allow-origin", "*")|,
        "path" => "lib/web/router.ex",
        "kind" => "code",
        "domain_pack" => "software"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "software.cors_wildcard"))
    assert result.decision == "block"
  end

  test "catches Req.post with email (gdpr third_party_data_transfer)" do
    result =
      FastPath.scan(%{
        "content" =>
          ~s|Req.post("https://analytics.example.com/track", json: %{email: user.email})|,
        "path" => "lib/analytics/tracker.ex",
        "kind" => "code",
        "domain_pack" => "gdpr"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "gdpr.third_party_data_transfer"))
  end

  test "catches remote_ip in logs (gdpr personal_data_logging)" do
    result =
      FastPath.scan(%{
        "content" => "IO.puts conn.remote_ip",
        "path" => "lib/web/plug.ex",
        "kind" => "code",
        "domain_pack" => "gdpr"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "gdpr.personal_data_logging"))
  end

  test "catches protected Ecto fields in mass assignment" do
    result =
      FastPath.scan(%{
        "content" => """
        def changeset(order, attrs) do
          order
          |> cast(attrs, [:total_cents, :status, :user_id, :discount_percent, :refunded_amount])
          |> validate_required([:total_cents, :user_id])
        end
        """,
        "path" => "lib/shop/order.ex",
        "kind" => "code"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "security.mass_assignment"))
    assert result.decision == "block"
  end

  test "warns on public registration without rate limiting" do
    result =
      FastPath.scan(%{
        "content" => """
        def register(conn, %{"email" => email, "password" => password}) do
          %Accounts.User{}
          |> Accounts.User.changeset(%{"email" => email, "password" => password})
          |> Repo.insert!()

          json(conn, %{message: "Account created successfully"})
        end
        """,
        "path" => "lib/my_app_web/controllers/api_controller.ex",
        "kind" => "code",
        "domain_pack" => "software"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "software.missing_rate_limit"))
    assert result.decision in ["warn", "block"]
  end

  test "warns on logging raw request body and headers" do
    result =
      FastPath.scan(%{
        "content" => """
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Logger.info("Request body: \#{body}")
        Logger.info("Headers: \#{inspect(conn.req_headers)}")
        Logger.info("Remote IP: \#{inspect(conn.remote_ip)}")
        """,
        "path" => "lib/my_app_web/plugs/request_logger.ex",
        "kind" => "code",
        "domain_pack" => "software"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "software.sensitive_request_logging"))
    assert result.decision in ["warn", "block"]
  end

  test "blocks order lookup by URL id without ownership scope" do
    result =
      FastPath.scan(%{
        "content" => """
        def show(conn, %{"id" => id}) do
          order = Repo.get!(Order, id)
          json(conn, %{
            order_id: order.id,
            user_id: order.user_id,
            total: order.total_cents,
            items: order.items,
            shipping_address: order.shipping_address,
            payment_method: order.payment_last_four
          })
        end
        """,
        "path" => "lib/my_app_web/controllers/order_controller.ex",
        "kind" => "code",
        "domain_pack" => "ecommerce"
      })

    assert Enum.any?(result.findings, &(&1.rule_id == "ecommerce.idor_order_lookup"))
    assert result.decision == "block"
  end
end
