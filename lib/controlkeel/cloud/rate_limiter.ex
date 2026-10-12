defmodule ControlKeel.Cloud.RateLimiter do
  @moduledoc """
  Per-workspace token-bucket rate limiter for `/cloud/v1` HTTP routes.

  Backed by a single named ETS table. The GenServer is only responsible
  for table ownership at boot; the hot path (`hit/2`) reads and writes
  ETS directly with `write_concurrency: true` for parallel-process throughput.

  ## Algorithm

  Classic token bucket. Each workspace gets a bucket of size `:burst`.
  Tokens refill at `:refill_per_sec`. A request that finds at least 1 token
  consumes it and returns `:ok`. A request that finds < 1 token returns
  `{:error, :rate_limited, retry_after_seconds}`.

  ## Defaults

      burst:           60 requests
      refill_per_sec:   1 token

  Override per environment via:

      config :controlkeel, :cloud_rate_limit, %{burst: 120, refill_per_sec: 2}

  ## Scope

  **Single-node only.** Each Fly machine maintains its own bucket. For
  multi-node coordination, replace the ETS backend with a distributed
  store (NATS KV, Redis). That's a separate slice — out of scope for P3.5.
  """

  use GenServer

  @table :ck_cloud_rate_limiter
  @default_burst 60
  @default_refill_per_sec 1

  @typedoc "Result of a hit attempt."
  @type result :: :ok | {:error, :rate_limited, non_neg_integer()}

  # ── Public API ──────────────────────────────────────────────────────

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Hit the bucket for an arbitrary key (not just a workspace id).

  Same token-bucket semantics as `hit/2`, but accepts any term. Used for
  per-IP throttling on unauthenticated surfaces and per-secret throttling on
  short-lived codes, where there is no workspace to key on yet. Callers
  namespace their keys so they cannot collide with workspace buckets.
  """
  @spec hit_key(term(), keyword()) :: result()
  def hit_key(key, opts \\ []) when not is_nil(key) do
    burst = Keyword.get(opts, :burst, configured(:burst, @default_burst))

    refill =
      Keyword.get(opts, :refill_per_sec, configured(:refill_per_sec, @default_refill_per_sec))

    now_ms = System.monotonic_time(:millisecond)
    do_hit(key, burst, refill, now_ms)
  end

  @doc """
  Consume one token for `workspace_id`. Returns `:ok` on success or
  `{:error, :rate_limited, retry_after_seconds}` when the bucket is empty.
  """
  @spec hit(integer(), keyword()) :: result()
  def hit(workspace_id, opts \\ []) when is_integer(workspace_id) do
    burst = Keyword.get(opts, :burst, configured(:burst, @default_burst))

    refill =
      Keyword.get(opts, :refill_per_sec, configured(:refill_per_sec, @default_refill_per_sec))

    now_ms = System.monotonic_time(:millisecond)
    do_hit(workspace_id, burst, refill, now_ms)
  end

  @doc "Reset all buckets. Useful in tests."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # ── GenServer ──────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Idempotent: if the table already exists (e.g. an earlier test crashed
    # the owner but the table survived), reuse it.
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])

      _existing ->
        :ok
    end

    {:ok, %{}}
  end

  # ── Token-bucket math ──────────────────────────────────────────────

  defp do_hit(key, burst, refill, now_ms) do
    case :ets.lookup(@table, key) do
      [] ->
        # First request from this workspace: hand out a burst-1 bucket.
        :ets.insert(@table, {key, burst - 1, now_ms})
        :ok

      [{^key, tokens, last_ms}] ->
        elapsed_s = max(now_ms - last_ms, 0) / 1000
        refilled = min(burst, tokens + elapsed_s * refill)

        if refilled >= 1 do
          :ets.insert(@table, {key, refilled - 1, now_ms})
          :ok
        else
          retry_after = max(ceil_div(1 - refilled, refill), 1)
          {:error, :rate_limited, retry_after}
        end
    end
  end

  defp ceil_div(_, 0), do: 1

  defp ceil_div(numer, denom) do
    quot = numer / denom
    if quot == trunc(quot), do: trunc(quot), else: trunc(quot) + 1
  end

  defp configured(key, default) do
    :controlkeel
    |> Application.get_env(:cloud_rate_limit, %{})
    |> Map.get(key, default)
  end
end
