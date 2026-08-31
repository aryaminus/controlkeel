defmodule ControlKeelWeb.ObservabilityController do
  use ControlKeelWeb, :controller

  # Mirrors LiveAuth.require_cloud_auth: passthrough in local mode, requires a
  # signed-in user in cloud/self_hosted, and verifies org ownership of the
  # session's workspace to prevent cross-org data leakage (CK-AUTH-001).
  plug ControlKeelWeb.Plugs.RequireSessionAuth

  alias ControlKeel.Observability.Telemetry
  alias ControlKeel.Platform

  @audit_formats ~w(json csv pdf)
  @audit_content_types %{
    "json" => "application/json",
    "csv" => "text/csv",
    "pdf" => "application/pdf"
  }

  def export_session(conn, %{"id" => id}) do
    case Telemetry.export_session(id) do
      {:ok, envelope} ->
        json(conn, envelope)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session not found"})

      {:error, :invalid_session_id} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "session id must be an integer"})
    end
  end

  # Thin wrapper over Platform.export_audit_log/3 — the payload is served
  # verbatim (no re-rendering), with the same attachment disposition as the
  # API-token route GET /api/v1/sessions/:id/audit-log.
  def export_audit_log(conn, %{"id" => id, "format" => format}) do
    with {:ok, format} <- validate_audit_format(format),
         {:ok, session_id} <- parse_session_id(id),
         {:ok, %{payload: payload}} <-
           Platform.export_audit_log(session_id, format, actor: "web") do
      conn
      |> put_resp_content_type(@audit_content_types[format])
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"audit-log-#{session_id}.#{format}\""
      )
      |> send_resp(200, payload)
    else
      {:error, :unsupported_format} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "format must be json, csv, or pdf"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session not found"})

      {:error, :renderer_unavailable} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "pdf_export_unavailable"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  defp validate_audit_format(format) when format in @audit_formats, do: {:ok, format}
  defp validate_audit_format(_format), do: {:error, :unsupported_format}

  defp parse_session_id(id) do
    case Integer.parse(id) do
      {session_id, ""} -> {:ok, session_id}
      _ -> {:error, :not_found}
    end
  end
end
