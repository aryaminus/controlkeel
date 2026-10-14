defmodule ControlKeelWeb.FallbackController do
  use ControlKeelWeb, :controller

  @moduledoc """
  Handles catch-all routes that don't match any defined route.
  Returns proper 404 status codes for both HTML and JSON requests.
  """

  def not_found(conn, _params) do
    conn = put_status(conn, :not_found)

    if json_request?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> json(%{
        error: %{
          code: "not_found",
          message: "The requested resource was not found.",
          resolution:
            "Check the URL path and try again. " <>
              "Available resources are listed at /openapi.json and /llms.txt."
        }
      })
    else
      conn
      |> put_resp_content_type("text/markdown")
      |> send_resp(404, not_found_markdown())
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] ->
        String.contains?(accept, "application/json") or
          String.ends_with?(accept, "+json")

      [] ->
        false
    end
  end

  defp not_found_markdown do
    """
    # 404 — Page Not Found

    The page you're looking for doesn't exist or has been moved.

    ## Helpful links

    - [Home](https://controlkeel.com/)
    - [Documentation](https://controlkeel.com/docs/getting-started)
    - [API Reference](https://controlkeel.com/developers)
    - [OpenAPI Spec](https://controlkeel.com/openapi.json)
    - [llms.txt](https://controlkeel.com/llms.txt)
    - [Sitemap](https://controlkeel.com/sitemap.xml)
    """
  end
end
