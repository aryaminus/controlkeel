defmodule ControlKeel.Intent.TelemetryTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.IntentFixtures

  alias ControlKeel.Intent

  setup %{conn: conn} do
    original = Application.get_env(:controlkeel, ControlKeel.Intent)

    on_exit(fn ->
      :telemetry.detach("controlkeel-intent-telemetry-#{inspect(self())}")

      if original do
        Application.put_env(:controlkeel, ControlKeel.Intent, original)
      else
        Application.delete_env(:controlkeel, ControlKeel.Intent)
      end
    end)

    :telemetry.attach_many(
      "controlkeel-intent-telemetry-#{inspect(self())}",
      [
        [:controlkeel, :intent, :compiler, :fallback],
        [:controlkeel, :intent, :compiler, :success],
        [:controlkeel, :intent, :compiler, :failure],
        [:controlkeel, :intent, :interview, :started],
        [:controlkeel, :intent, :interview, :step_completed]
      ],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      self()
    )

    {:ok, conn: conn}
  end

  test "compiler success, fallback, and failure events emit expected metadata" do
    openai = Bypass.open()
    anthropic = Bypass.open()

    Bypass.expect(openai, "POST", "/v1/responses", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{"model" => "gpt-5.4", "output_text" => "not-json"})
      )
    end)

    Bypass.expect_once(anthropic, "POST", "/v1/messages", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "claude-sonnet-4-5",
          "content" => [%{"type" => "tool_use", "input" => provider_brief_payload()}]
        })
      )
    end)

    Application.put_env(
      :controlkeel,
      ControlKeel.Intent,
      %{
        default_provider: nil,
        dev_fallback: false,
        providers: %{
          openai: %{
            api_key: "openai-test",
            base_url: "http://127.0.0.1:#{openai.port}",
            model: "gpt-5.4"
          },
          anthropic: %{
            api_key: "anthropic-test",
            base_url: "http://127.0.0.1:#{anthropic.port}",
            model: "claude-sonnet-4-5"
          },
          openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
          ollama: %{base_url: "http://127.0.0.1:1", model: "unused"}
        }
      }
    )

    assert {:ok, _brief} =
             Intent.compile(sample_intent_attrs(),
               providers: [:openai, :anthropic],
               allow_dev_fallback: false
             )

    assert_receive {:telemetry, [:controlkeel, :intent, :compiler, :fallback], %{count: 1},
                    metadata}

    assert metadata.provider == "openai"
    assert metadata.next_provider == "anthropic"

    assert_receive {:telemetry, [:controlkeel, :intent, :compiler, :success], %{count: 1},
                    metadata}

    assert metadata.provider == "anthropic"
    assert metadata.model == "claude-sonnet-4-5"

    Application.put_env(
      :controlkeel,
      ControlKeel.Intent,
      %{
        default_provider: nil,
        dev_fallback: false,
        providers: %{
          openai: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
          anthropic: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
          openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
          ollama: %{base_url: "http://127.0.0.1:1", model: "unused"}
        }
      }
    )

    assert {:error, :no_provider_succeeded} =
             Intent.compile(sample_intent_attrs(),
               providers: [:ollama],
               allow_dev_fallback: false
             )

    assert_receive {:telemetry, [:controlkeel, :intent, :compiler, :failure], %{count: 1},
                    metadata}

    assert metadata.provider == "none"
  end

  test "interview lifecycle telemetry emits at step boundaries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/start")

    render_submit(
      form(view, "form", launch: %{"occupation" => "healthcare", "agent" => "claude"})
    )

    render_submit(
      form(view, "form",
        launch: %{
          "project_name" => "Clinic Intake",
          "idea" =>
            "Build a patient intake workflow for a small clinic with staff review and exports."
        }
      )
    )

    render_submit(
      form(view, "form",
        launch: %{
          "interview_answers" => %{
            "who_uses_it" => "Front desk staff and clinic admins",
            "data_involved" => "Patient names, insurance notes, scheduling details",
            "first_release" => "Intake form, review queue, export",
            "constraints" => "Local-first deploy, approval before production"
          }
        }
      )
    )

    assert_receive {:telemetry, [:controlkeel, :intent, :interview, :started], %{count: 1},
                    metadata}

    assert metadata.occupation == "healthcare"
    assert metadata.domain_pack == "healthcare"

    assert_receive {:telemetry, [:controlkeel, :intent, :interview, :step_completed], %{count: 1},
                    %{step: 1}}

    assert_receive {:telemetry, [:controlkeel, :intent, :interview, :step_completed], %{count: 1},
                    %{step: 2}}

    assert_receive {:telemetry, [:controlkeel, :intent, :interview, :step_completed], %{count: 1},
                    %{step: 3}}
  end
end
