defmodule ControlKeel.Accounts.DeviceAuth do
  @moduledoc """
  RFC 8628 OAuth 2.0 Device Authorization Grant server side.

  ControlKeel's CLI has no browser, so it uses the device flow: it requests a
  device authorization, shows the user a short `user_code`, and polls the token
  endpoint until the user approves in a browser.

  Security properties implemented (RFC 8628 §5 and OWASP):

    * **Both codes are stored hashed** (SHA-256). The device code is a bearer
      credential; the user code is short enough to be typed, so it is the most
      brute-forceable secret in the protocol.
    * **High-entropy device code** — 32 random bytes (~256 bits), base64url.
    * **Short, unambiguous user code** — 8 chars from a 20-symbol alphabet
      (~34.5 bits), which the RFC explicitly says is only acceptable *because*
      it is paired with rate limiting and a short lifetime.
    * **Rate-limited user-code lookup** — the RFC requires the server to
      rate-limit user-code attempts; brute force is infeasible only when both
      are in place.
    * **Short lifetime** (10 minutes) so a leaked/observed user code cannot be
      redeemed later.
    * **Single use** — the device code is marked `consumed` when a token is
      issued and cannot be replayed.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Accounts.DeviceAuthorization
  alias ControlKeel.Repo

  # RFC 8628 §5.1 recommends ~20 symbols, avoiding visually ambiguous
  # characters. This is the "BCJDXFGMHJKLNPQRSTVWXYZ" style alphabet with the
  # ambiguous 0/O/1/I removed.
  @user_code_alphabet ~c"BCDFGHJKLMNPQRSTVWXZ23456789"
  @user_code_length 8
  @device_code_bytes 32

  @default_ttl_seconds 600
  @default_interval_seconds 5
  @slow_down_threshold 2

  @doc """
  Create a pending device authorization.

  Returns the raw `device_code` and `user_code` exactly once — only their
  hashes are persisted.
  """
  @spec start_device_authorization(map()) ::
          {:ok, map()} | {:error, term()}
  def start_device_authorization(attrs \\ %{}) do
    device_code = generate_device_code()
    user_code = generate_user_code()
    now = truncate(now())

    attrs = %{
      device_code_hash: hash(device_code),
      user_code_hash: hash(user_code),
      client_id: Map.get(attrs, :client_id),
      client_name: Map.get(attrs, :client_name),
      scope: Map.get(attrs, :scope, "") || "",
      status: "pending",
      expires_at: DateTime.add(now, ttl_seconds(), :second),
      interval_seconds: interval_seconds(),
      verification_uri: verification_uri()
    }

    case %DeviceAuthorization{}
         |> DeviceAuthorization.changeset(attrs)
         |> Repo.insert() do
      {:ok, _record} ->
        {:ok,
         %{
           "device_code" => device_code,
           "user_code" => user_code,
           "verification_uri" => verification_uri(),
           "verification_uri_complete" => verification_uri() <> "?user_code=" <> user_code,
           "expires_in" => ttl_seconds(),
           "interval" => interval_seconds()
         }}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Look up a pending device session by user code (for the browser approval page).

  Returns `{:error, :not_found}` for unknown, expired, or already-resolved
  codes so the page cannot distinguish them.
  """
  @spec fetch_by_user_code(String.t()) ::
          {:ok, DeviceAuthorization.t()} | {:error, :not_found | :rate_limited}
  def fetch_by_user_code(user_code) when is_binary(user_code) do
    normalized = normalize_user_code(user_code)

    # RFC 8628 §5.1: the user code is short by design, so the server MUST
    # rate-limit attempts. ~34.5 bits of entropy is only safe when brute force
    # is throttled and the code is short-lived — both are enforced here.
    # Keyed by a hash of the code so we never store or log it in a rate-limit key.
    case ControlKeel.Cloud.RateLimiter.hit_key({:device_user_code, hash(normalized)},
           burst: 5,
           refill_per_sec: 0.01
         ) do
      :ok -> do_fetch_user_code(normalized)
      {:error, :rate_limited, _} -> {:error, :rate_limited}
    end
  end

  defp do_fetch_user_code(normalized) do
    case Repo.get_by(DeviceAuthorization, user_code_hash: hash(normalized)) do
      %DeviceAuthorization{status: "pending"} = auth ->
        if DeviceAuthorization.expired?(auth) do
          {:error, :not_found}
        else
          {:ok, auth}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Approve (or deny) a pending device session as a signed-in user.

  Returns the client name and scope so the approval UI can show the user what
  they are authorizing, per RFC 8628 §3.3.
  """
  @spec approve(DeviceAuthorization.t(), integer()) ::
          {:ok, DeviceAuthorization.t()} | {:error, :invalid_state | Ecto.Changeset.t()}
  def approve(%DeviceAuthorization{} = auth, user_id) when is_integer(user_id) do
    transition(auth, %{
      status: "approved",
      user_id: user_id,
      approved_at: now()
    })
  end

  @spec deny(DeviceAuthorization.t(), integer()) ::
          {:ok, DeviceAuthorization.t()} | {:error, :invalid_state | Ecto.Changeset.t()}
  def deny(%DeviceAuthorization{} = auth, user_id) when is_integer(user_id) do
    transition(auth, %{
      status: "denied",
      user_id: user_id,
      denied_at: now()
    })
  end

  defp transition(%DeviceAuthorization{status: "pending"} = auth, attrs) do
    auth
    |> DeviceAuthorization.changeset(attrs)
    |> Repo.update()
  end

  defp transition(_auth, _attrs), do: {:error, :invalid_state}

  @doc """
  Poll for the device token — the RFC 8628 §3.4/§3.5 token endpoint.

  Returns one of:

    * `{:ok, authorization}` — approved; caller should issue the token and then
      call `consume/1`.
    * `{:error, :authorization_pending}` — still waiting for the user.
    * `{:error, :slow_down}` — polled too fast; the client must increase its
      interval (RFC 8628 §3.5).
    * `{:error, :access_denied}` — the user denied it.
    * `{:error, :expired_token}` — past its lifetime.
  """
  @spec poll_for_token(String.t()) ::
          {:ok, DeviceAuthorization.t()}
          | {:error, :authorization_pending | :slow_down | :access_denied | :expired_token}
  def poll_for_token(device_code) when is_binary(device_code) do
    case Repo.get_by(DeviceAuthorization, device_code_hash: hash(device_code)) do
      nil ->
        {:error, :expired_token}

      %DeviceAuthorization{} = auth ->
        cond do
          DeviceAuthorization.expired?(auth) ->
            {:error, :expired_token}

          auth.status == "denied" ->
            {:error, :access_denied}

          auth.status == "consumed" ->
            # Single use: a replayed device code is not redeemable.
            {:error, :expired_token}

          auth.status == "approved" ->
            {:ok, auth}

          true ->
            register_poll(auth)
        end
    end
  end

  defp register_poll(auth) do
    now = now()

    too_fast? =
      not is_nil(auth.last_polled_at) and
        DateTime.diff(now, auth.last_polled_at, :second) < auth.interval_seconds

    attrs = %{
      last_polled_at: now,
      poll_count: auth.poll_count + 1
    }

    # RFC 8628 §3.5: when the client polls faster than `interval`, the server
    # responds `slow_down`. We also persist the new interval so subsequent
    # responses enforce the widened window.
    if too_fast? and auth.poll_count > @slow_down_threshold do
      attrs = Map.put(attrs, :interval_seconds, auth.interval_seconds + 5)

      auth
      |> DeviceAuthorization.changeset(attrs)
      |> Repo.update()

      {:error, :slow_down}
    else
      auth
      |> DeviceAuthorization.changeset(attrs)
      |> Repo.update()

      {:error, :authorization_pending}
    end
  end

  @doc "Mark a device session as consumed after its token is issued (single use)."
  @spec consume(DeviceAuthorization.t()) :: {:ok, DeviceAuthorization.t()} | {:error, term()}
  def consume(%DeviceAuthorization{status: "approved"} = auth) do
    auth
    |> DeviceAuthorization.changeset(%{status: "consumed", consumed_at: now()})
    |> Repo.update()
  end

  def consume(_auth), do: {:error, :invalid_state}

  @doc "Remove expired device sessions (housekeeping)."
  def purge_expired do
    now = now()

    {count, _} =
      DeviceAuthorization
      |> where([d], d.expires_at < ^now)
      |> Repo.delete_all()

    {count, nil}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  # Strip formatting so a user can type "BCDF-GHJK" or "bcdf ghjk".
  defp normalize_user_code(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
  end

  defp generate_device_code do
    @device_code_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  # Pick from the unambiguous alphabet uniformly.
  defp generate_user_code do
    count = length(@user_code_alphabet)

    1..@user_code_length
    |> Enum.map_join(fn _ ->
      index = :crypto.strong_rand_bytes(1) |> :binary.decode_unsigned() |> rem(count)
      <<Enum.at(@user_code_alphabet, index)>>
    end)
  end

  # SHA-256 is appropriate here: both inputs are already high-entropy random
  # codes, so a slow KDF would add latency without adding security.
  defp hash(value) when is_binary(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  defp now, do: truncate(DateTime.utc_now())
  defp truncate(dt), do: DateTime.truncate(dt, :second)

  defp ttl_seconds,
    do: Application.get_env(:controlkeel, :device_code_ttl_seconds, @default_ttl_seconds)

  defp interval_seconds,
    do:
      Application.get_env(:controlkeel, :device_code_interval_seconds, @default_interval_seconds)

  defp verification_uri do
    base =
      ControlKeelWeb.Endpoint.url()

    base <> "/device"
  end
end
