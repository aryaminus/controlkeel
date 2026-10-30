defmodule ControlKeelWeb.ErrorJSON do
  @moduledoc """
  Structured JSON error responses for the ControlKeel API.

  Returns machine-readable error objects with code, message, and resolution hints
  so AI agents can parse and act on errors programmatically.
  """

  def render("404.json", _assigns) do
    %{
      error: %{
        code: "not_found",
        message: "The requested resource was not found.",
        resolution:
          "Check the URL path and try again. Available resources are listed at /openapi.json and /llms.txt."
      }
    }
  end

  def render("401.json", _assigns) do
    %{
      error: %{
        code: "unauthorized",
        message: "Authentication required. Provide a valid API key.",
        resolution:
          "Include an Authorization header: `Authorization: Bearer <your-api-key>`. Generate keys under an organization workspace at /:org_slug/workspaces/:workspace_slug/service-accounts."
      }
    }
  end

  def render("403.json", _assigns) do
    %{
      error: %{
        code: "forbidden",
        message: "You do not have permission to access this resource.",
        resolution:
          "Check your API key permissions or contact your workspace administrator to grant access."
      }
    }
  end

  def render("422.json", _assigns) do
    %{
      error: %{
        code: "unprocessable_entity",
        message: "The request was well-formed but semantically invalid.",
        resolution:
          "Review the request body against the schema at /openapi.json and fix the invalid fields."
      }
    }
  end

  def render("500.json", _assigns) do
    %{
      error: %{
        code: "internal_server_error",
        message: "An unexpected error occurred on the server.",
        resolution:
          "Retry the request. If the problem persists, report it at https://github.com/aryaminus/controlkeel/issues."
      }
    }
  end

  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)

    %{
      error: %{
        code: template |> String.replace(".json", "") |> String.replace("-", "_"),
        message: status,
        resolution: "Check the API documentation at /developers for usage guidance."
      }
    }
  end
end
