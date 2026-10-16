defmodule ControlKeelWeb.Plugs.IpRateLimit do
  @moduledoc """
  Per-IP rate limit for **unauthenticated** token-consuming surfaces.

  `CloudRateLimit` is per-workspace and correctly passes through when there is
  no workspace context, which makes it the wrong tool before authentication.
  The surfaces this protects are unauthenticated by design and *distinguish*
  valid from invalid tokens in their responses:

    * `GET /invitations/:token` → `:ready` / `:already_accepted` / `:invalid`
    * `POST /cloud/v1/workspaces/register` → `invalid_invitation_token` vs `201`

  With 256-bit tokens brute force is infeasible, so this is defence in depth:
  a throttle layer that absorbs enumeration attempts and would meaningfully
  blunt any future reduction in token entropy. Uses the same token bucket as the
  cloud limiter via `RateLimiter.hit_key/2`, keyed by a namespaced IP hash so it
  cannot collide with workspace buckets.

  Returns 429 with `Retry-After` on overflow.
  """

  import Plug.Conn

  alias ControlKeel.Cloud.RateLimiter

  @default_burst 20
  @default_refill_per_sec 0.5

  def init(opts), do: opts

  def call(conn, opts) do
    key = bucket_key(conn, opts)

    case RateLimiter.hit_key(key,
           burst: Keyword.get(opts, :burst, @default_burst),
           refill_per_sec: Keyword.get(opts, :refill_per_sec, @default_refill_per_sec)
         ) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.json(%{error: "rate_limited", retry_after: retry_after})
        |> halt()
    end
  end

  # Namespace by bucket name so separate oracles have independent budgets.
  defp bucket_key(conn, opts) do
    prefix = Keyword.get(opts, :bucket, "ip")
    "ip:#{prefix}:#{ip(conn)}"
  end

  defp ip(%Plug.Conn{remote_ip: ip}) when is_tuple(ip),
    do: ip |> Tuple.to_list() |> Enum.join(".")

  defp ip(_conn), do: "unknown"
end
