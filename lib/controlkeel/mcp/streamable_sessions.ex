defmodule ControlKeel.Mcp.StreamableSessions do
  @moduledoc """
  Session registry for the Streamable HTTP MCP transport (MCP 2025-03-26).

  The server assigns an `Mcp-Session-Id` response header on `initialize`,
  validates it on subsequent requests, and terminates it on `DELETE /mcp`.
  Sessions are advisory identification (the transport is otherwise
  stateless); unknown or expired ids must yield 404 per spec.

  Storage is an ETS table owned by this module, started under the app
  supervision tree when hosted MCP is available. Entries carry a TTL and
  are evicted lazily on read plus on every sweep.
  """

  use GenServer

  @table :controlkeel_mcp_streamable_sessions
  @default_ttl_minutes 60
  @sweep_interval :timer.minutes(5)

  # ─── Client API ───────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new session and returns its id (ULID-based).
  """
  def issue do
    session_id = "mcp_" <> ControlKeel.Cloud.Telemetry.Envelope.ulid()
    ttl = ttl_seconds()
    now = System.os_time(:second)

    :ets.insert_new(@table, {session_id, now + ttl})
    session_id
  end

  @doc """
  True when the session id is known and unexpired (touches it).
  False otherwise.
  """
  def valid?(session_id) when is_binary(session_id) do
    now = System.os_time(:second)

    case :ets.lookup(@table, session_id) do
      [{^session_id, expires_at}] when expires_at > now ->
        :ets.insert(@table, {session_id, now + ttl_seconds()})
        true

      _ ->
        false
    end
  end

  def valid?(_), do: false

  @doc """
  Removes a session. Returns :ok regardless (idempotent termination).
  """
  def terminate(session_id) when is_binary(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  def terminate(_), do: :ok

  @doc """
  Number of live sessions (diagnostics/tests).
  """
  def count do
    sweep()
    :ets.info(@table, :size)
  end

  # ─── GenServer ────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

    schedule_sweep()
    {:ok, table}
  end

  @impl true
  def handle_info(:sweep, table) do
    sweep()
    schedule_sweep()
    {:noreply, table}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)

  defp sweep do
    if :ets.whereis(@table) != :undefined do
      now = System.os_time(:second)

      :ets.safe_fixtable(@table, true)

      :ets.foldl(
        fn {session_id, expires_at}, _acc ->
          if expires_at <= now, do: :ets.delete(@table, session_id)
          :ok
        end,
        :ok,
        @table
      )

      :ets.safe_fixtable(@table, false)
    end

    :ok
  end

  defp ttl_seconds do
    case Application.get_env(:controlkeel, :mcp_session_ttl_minutes) do
      minutes when is_integer(minutes) and minutes > 0 -> minutes * 60
      _ -> @default_ttl_minutes * 60
    end
  end
end
