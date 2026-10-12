defmodule ControlKeel.CLI.Dispatch.Login do
  @moduledoc """
  CLI sign-in via the OAuth 2.0 Device Authorization Grant (RFC 8628, issue #251).

  `controlkeel login --server <url>` runs the device flow end to end:

    1. POST to `<server>/device_authorization` and receive `device_code`,
       `user_code`, `verification_uri`, `interval`, `expires_in`.
    2. Print the user code and URL for the user to open in a browser.
    3. Poll `<server>/oauth/device_token` at `interval`, honouring the RFC's
       `slow_down` signal by widening the wait, until the user approves.
    4. Persist the issued `access_token` (mode 0600).

  `controlkeel logout` clears the stored token; `controlkeel whoami` prints the
  signed-in identity.
  """

  alias ControlKeel.CLI.LoginStore

  @grant_type "urn:ietf:params:oauth:grant-type:device_code"

  def run_command(%{command: :login, options: options}, _project_root) do
    server = normalize_server(Map.get(options, :server) || default_server())

    case start_device(server) do
      {:ok, payload} ->
        case poll_until_done(server, payload) do
          {:ok, token} -> persist(token, server)
          {:error, reason} -> report({:error, reason})
        end

      {:error, reason} ->
        report({:error, "device_authorization_failed: #{inspect(reason)}"})
    end
  end

  def run_command(%{command: :logout}, _project_root) do
    case LoginStore.delete() do
      :ok -> report({:ok, "Signed out."})
      {:error, reason} -> report({:error, "Could not clear credentials: #{inspect(reason)}"})
    end
  end

  def run_command(%{command: :whoami, options: options}, _project_root) do
    server = normalize_server(Map.get(options, :server) || default_server())

    case LoginStore.load() do
      {:ok, %{"email" => email}} ->
        report({:ok, "Signed in as #{email} (#{server})"})

      :error ->
        report({:error, "Not signed in. Run: controlkeel login --server #{server}"})
    end
  end

  defp persist(%{"access_token" => token, "email" => email}, server) do
    case LoginStore.save(%{
           "access_token" => token,
           "email" => email,
           "server" => server
         }) do
      :ok -> report({:ok, "Signed in as #{email}."})
      {:error, reason} -> report({:error, "Could not save credentials: #{inspect(reason)}"})
    end
  end

  # ── Device flow steps ─────────────────────────────────────────────────────

  defp start_device(server) do
    case Req.post("#{server}/device_authorization",
           json: %{"client_id" => "controlkeel-cli", "scope" => "cli"},
           decode_json: [keys: :strings]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll_until_done(server, payload) do
    interval = max(payload["interval"] || 5, 1)
    deadline = System.monotonic_time(:second) + (payload["expires_in"] || 600)

    print_instructions(payload)

    do_poll(server, payload["device_code"], interval, deadline)
  end

  defp do_poll(server, device_code, interval, deadline) do
    if System.monotonic_time(:second) >= deadline do
      {:error, :expired_token}
    else
      # RFC 8628 §3.4: wait at least `interval` between polls.
      Process.sleep(interval * 1000)

      case poll_once(server, device_code) do
        {:ok, token} ->
          {:ok, token}

        {:pending, new_interval} ->
          do_poll(server, device_code, new_interval, deadline)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp poll_once(server, device_code) do
    case Req.post("#{server}/oauth/device_token",
           json: %{"grant_type" => @grant_type, "device_code" => device_code},
           decode_json: [keys: :strings]
         ) do
      {:ok, %{status: 200, body: body}} ->
        # The server includes the approver's identity so whoami works locally.
        {:ok, body}

      {:ok, %{status: 400, body: %{"error" => "authorization_pending"}}} ->
        {:pending, 5}

      {:ok, %{status: 400, body: %{"error" => "slow_down"}}} ->
        # RFC 8628: back off.
        {:pending, 10}

      {:ok, %{status: 400, body: %{"error" => code}}} ->
        {:error, code}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp print_instructions(payload) do
    IO.puts("Your ControlKeel login code: #{payload["user_code"]}")

    IO.puts(
      "Open #{payload["verification_uri_complete"] || payload["verification_uri"]} and enter it."
    )

    IO.puts("Waiting for authorization…")
  end

  defp normalize_server(server) do
    String.trim_trailing(String.trim(server), "/")
  end

  defp default_server do
    System.get_env("CONTROLKEEL_SERVER") || "http://localhost:4000"
  end

  defp report({:ok, message}), do: {:ok, message}
  defp report({:error, message}), do: {:error, message}
end
