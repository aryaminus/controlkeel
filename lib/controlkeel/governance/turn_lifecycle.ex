defmodule ControlKeel.Governance.TurnLifecycle do
  @moduledoc false

  # Manages turn context for provider-neutral runtimes (§5 of spec).
  # Opens/closes turn contexts, accumulates evidence and decisions during turns,
  # triggers proof export at turn close.

  alias ControlKeel.OrchestrationEvents

  use GenServer

  @table :ck_turn_lifecycle

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Open a new turn context. Returns the turn state.
  """
  def open(session_id, thread_id, turn_id, opts \\ []) do
    GenServer.call(__MODULE__, {:open, session_id, thread_id, turn_id, opts})
  end

  @doc """
  Record a request evaluation within the current turn.
  """
  def record_decision(session_id, thread_id, turn_id, request_id, decision) do
    GenServer.call(
      __MODULE__,
      {:record_decision, session_id, thread_id, turn_id, request_id, decision}
    )
  end

  @doc """
  Record evidence (finding, review state, etc.) within the current turn.
  """
  def record_evidence(session_id, thread_id, turn_id, evidence) do
    GenServer.call(__MODULE__, {:record_evidence, session_id, thread_id, turn_id, evidence})
  end

  @doc """
  Close a turn context. Returns the final turn state with accumulated evidence.
  Triggers proof export hook if configured.
  """
  def close(session_id, thread_id, turn_id, opts \\ []) do
    GenServer.call(__MODULE__, {:close, session_id, thread_id, turn_id, opts})
  end

  @doc """
  Get the current state of a turn.
  """
  def get_state(session_id, thread_id, turn_id) do
    GenServer.call(__MODULE__, {:get_state, session_id, thread_id, turn_id})
  end

  @doc """
  List all active turns for a session.
  """
  def active_turns(session_id) do
    GenServer.call(__MODULE__, {:active_turns, session_id})
  end

  # GenServer

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:open, session_id, thread_id, turn_id, opts}, _from, state) do
    key = turn_key(session_id, thread_id, turn_id)

    turn_state = %{
      session_id: session_id,
      thread_id: thread_id,
      turn_id: turn_id,
      agent_id: Keyword.get(opts, :agent_id),
      policy_mode: Keyword.get(opts, :policy_mode, "full_access"),
      opened_at: DateTime.utc_now(),
      decisions: [],
      evidence: [],
      status: :open
    }

    :ets.insert(@table, {key, turn_state})

    {:reply, turn_state, state}
  end

  @impl true
  def handle_call(
        {:record_decision, session_id, thread_id, turn_id, request_id, decision},
        _from,
        state
      ) do
    key = turn_key(session_id, thread_id, turn_id)

    case :ets.lookup(@table, key) do
      [{^key, turn_state}] ->
        updated =
          Map.update!(turn_state, :decisions, fn d ->
            [%{request_id: request_id, decision: decision, recorded_at: DateTime.utc_now()} | d]
          end)

        :ets.insert(@table, {key, updated})
        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :turn_not_found}, state}
    end
  end

  @impl true
  def handle_call({:record_evidence, session_id, thread_id, turn_id, evidence}, _from, state) do
    key = turn_key(session_id, thread_id, turn_id)

    case :ets.lookup(@table, key) do
      [{^key, turn_state}] ->
        updated =
          Map.update!(turn_state, :evidence, fn e ->
            [Map.put(evidence, :recorded_at, DateTime.utc_now()) | e]
          end)

        :ets.insert(@table, {key, updated})
        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :turn_not_found}, state}
    end
  end

  @impl true
  def handle_call({:close, session_id, thread_id, turn_id, opts}, _from, state) do
    key = turn_key(session_id, thread_id, turn_id)

    case :ets.lookup(@table, key) do
      [{^key, turn_state}] ->
        final =
          turn_state
          |> Map.put(:status, :closed)
          |> Map.put(:closed_at, DateTime.utc_now())
          |> Map.put(:summary, summarize_turn(turn_state))

        # Trigger proof export hook if applicable
        maybe_export_proof(final, opts)

        # Remove from active table after close
        :ets.delete(@table, key)

        {:reply, {:ok, final}, state}

      [] ->
        {:reply, {:error, :turn_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_state, session_id, thread_id, turn_id}, _from, state) do
    key = turn_key(session_id, thread_id, turn_id)

    case :ets.lookup(@table, key) do
      [{^key, turn_state}] -> {:reply, {:ok, turn_state}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:active_turns, session_id}, _from, state) do
    turns =
      :ets.foldl(
        fn
          {_key, %{session_id: ^session_id} = turn}, acc -> [turn | acc]
          _entry, acc -> acc
        end,
        [],
        @table
      )

    {:reply, turns, state}
  end

  defp turn_key(session_id, thread_id, turn_id) do
    "#{session_id}:#{thread_id}:#{turn_id}"
  end

  defp summarize_turn(turn_state) do
    decisions = turn_state.decisions
    evidence = turn_state.evidence

    %{
      "decision_count" => length(decisions),
      "evidence_count" => length(evidence),
      "declined_count" => Enum.count(decisions, &(&1.decision.decision == :decline)),
      "finding_count" => Enum.count(evidence, &(&1.type == :finding || &1[:type] == "finding")),
      "status" =>
        if(length(decisions) > 0 and Enum.any?(decisions, &(&1.decision.decision == :decline)),
          do: "gated",
          else: "clean"
        )
    }
  end

  defp maybe_export_proof(turn_state, opts) do
    if Keyword.get(opts, :export_proof, false) do
      # Emit proof.ready event for orchestration consumers
      proof_ref = "turn:#{turn_state.turn_id}:#{System.unique_integer([:positive])}"

      OrchestrationEvents.proof_payload(%{
        type: "turn_proof",
        reference: proof_ref
      })
    end
  end
end
