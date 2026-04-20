defmodule ControlKeel.Governance.IdempotencyLedger do
  @moduledoc false

  # Idempotent write ledger for CK side effects.
  # Prevents duplicate finding/review/budget writes on reconnect/replay
  # by tracking (session_id, thread_id, turn_id, event_id, event_type) keys.

  use GenServer

  @table :ck_idempotency_ledger
  @ttl_ms :timer.hours(24)
  @cleanup_interval_ms :timer.minutes(5)
  @max_entries 100_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Check if a side effect has already been recorded.
  Returns {:ok, :new} if this is a new write, or {:ok, :duplicate} if seen before.
  """
  def check(key) do
    GenServer.call(__MODULE__, {:check, build_key(key)})
  end

  @doc """
  Record that a side effect has been written.
  Returns :ok.
  """
  def mark_written(key) do
    GenServer.call(__MODULE__, {:mark, build_key(key)})
  end

  @doc """
  Check and mark atomically. Returns :new if this is the first write,
  or :duplicate if already seen.
  """
  def check_and_mark(key) do
    GenServer.call(__MODULE__, {:check_and_mark, build_key(key)})
  end

  @doc """
  Build a dedupe key from a map with standard fields.
  """
  def build_key(attrs) when is_map(attrs) do
    session_id = to_string(attrs[:session_id] || attrs["session_id"] || "")
    thread_id = to_string(attrs[:thread_id] || attrs["thread_id"] || "")
    turn_id = to_string(attrs[:turn_id] || attrs["turn_id"] || "")

    event_id =
      to_string(
        attrs[:event_id] || attrs["event_id"] || attrs[:sequence] || attrs["sequence"] || ""
      )

    event_type = to_string(attrs[:event_type] || attrs["event_type"] || "")

    "#{session_id}:#{thread_id}:#{turn_id}:#{event_id}:#{event_type}"
  end

  def build_key(key) when is_binary(key), do: key

  @doc """
  Get current ledger size.
  """
  def size do
    GenServer.call(__MODULE__, :size)
  end

  @doc """
  Clear all entries.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:check, key}, _from, state) do
    result =
      case :ets.lookup(@table, key) do
        [{^key, _inserted_at}] -> {:ok, :duplicate}
        [] -> {:ok, :new}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:mark, key}, _from, state) do
    :ets.insert(@table, {key, System.system_time(:millisecond)})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:check_and_mark, key}, _from, state) do
    result =
      case :ets.lookup(@table, key) do
        [{^key, _inserted_at}] ->
          :duplicate

        [] ->
          :ets.insert(@table, {key, System.system_time(:millisecond)})
          :new
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    {:reply, :ets.info(@table, :size), state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    do_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  defp do_cleanup do
    now = System.system_time(:millisecond)
    cutoff = now - @ttl_ms

    # Evict expired entries
    :ets.foldl(
      fn {key, inserted_at}, acc ->
        if inserted_at < cutoff, do: [key | acc], else: acc
      end,
      [],
      @table
    )
    |> Enum.each(&:ets.delete(@table, &1))

    # If still over max, evict oldest
    size = :ets.info(@table, :size)

    if size > @max_entries do
      :ets.tab2list(@table)
      |> Enum.sort_by(fn {_key, inserted_at} -> inserted_at end)
      |> Enum.take(size - @max_entries)
      |> Enum.each(fn {key, _} -> :ets.delete(@table, key) end)
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
