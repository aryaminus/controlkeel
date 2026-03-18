defmodule ControlKeelWeb.OnboardingLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "user can complete onboarding, regenerate, and create a mission", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/start")

    assert html =~ "Choose the domain and primary agent"
    assert html =~ "Founder / Product Builder"

    assert render_submit(
             form(view, "form", launch: %{"occupation" => "healthcare", "agent" => "claude"})
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "form",
               launch: %{
                 "project_name" => "Clinic Intake",
                 "idea" =>
                   "Build a patient intake workflow for a small clinic with staff review and exports."
               }
             )
           ) =~ "Answer the guided interview"

    review_html =
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

    assert review_html =~ "Review the compiled brief"
    assert review_html =~ "Acceptance criteria"
    assert Mission.list_sessions() == []

    regenerated_html = render_click(element(view, "button[phx-click=\"regenerate\"]"))
    assert regenerated_html =~ "Review the compiled brief"
    assert Mission.list_sessions() == []

    render_click(element(view, "button[phx-click=\"accept\"]"))
    {path, _flash} = assert_redirect(view)

    assert path =~ "/missions/"

    redirected_html =
      conn
      |> Phoenix.ConnTest.recycle()
      |> get(path)
      |> html_response(200)

    assert redirected_html =~ "Mission control"
    assert length(Mission.list_sessions()) == 1
  end

  test "validation errors render and provider keys are not exposed in the browser", %{conn: conn} do
    original = Application.get_env(:controlkeel, ControlKeel.Intent)

    on_exit(fn ->
      if original do
        Application.put_env(:controlkeel, ControlKeel.Intent, original)
      else
        Application.delete_env(:controlkeel, ControlKeel.Intent)
      end
    end)

    Application.put_env(
      :controlkeel,
      ControlKeel.Intent,
      %{
        providers: %{
          openai: %{api_key: "sk-secret-test", base_url: "http://127.0.0.1:1", model: "gpt-5.4"}
        }
      }
    )

    {:ok, view, html} = live(conn, ~p"/start")
    refute html =~ "sk-secret-test"

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    error_html =
      render_submit(form(view, "form", launch: %{"project_name" => "Tiny", "idea" => "short"}))

    assert error_html =~ "Describe the product in a few concrete sentences."
    refute error_html =~ "sk-secret-test"
  end
end
