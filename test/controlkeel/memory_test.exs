defmodule ControlKeel.MemoryTest do
  use ControlKeel.DataCase

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  alias ControlKeel.Memory
  alias ControlKeel.Memory.Store.Pgvector

  defmodule StubEmbeddingProvider do
    def embed(text, _opts) do
      embedding =
        cond do
          String.contains?(String.downcase(text), "sql") -> [1.0, 0.0, 0.0]
          String.contains?(String.downcase(text), "xss") -> [0.0, 1.0, 0.0]
          true -> [0.0, 0.0, 1.0]
        end

      {:ok, %{embedding: embedding, provider: "deterministic", model: "deterministic-1"}}
    end
  end

  setup do
    previous = Application.get_env(:controlkeel, :memory_embedding_providers_override)

    Application.put_env(:controlkeel, :memory_embedding_providers_override, [
      {StubEmbeddingProvider, []}
    ])

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :memory_embedding_providers_override, previous)
      else
        Application.delete_env(:controlkeel, :memory_embedding_providers_override)
      end
    end)

    :ok
  end

  test "record/1 persists a searchable memory record" do
    session = session_fixture()

    assert {:ok, record} =
             Memory.record(%{
               workspace_id: session.workspace_id,
               session_id: session.id,
               record_type: "decision",
               title: "SQL mitigation learned",
               summary: "Always parameterize the query builder",
               body: "The previous SQL issue was fixed with placeholders.",
               tags: ["sql", "security"],
               source_type: "test",
               source_id: "decision-1",
               metadata: %{"domain_pack" => "software"}
             })

    result =
      Memory.search("parameterize sql",
        session_id: session.id,
        workspace_id: session.workspace_id
      )

    assert Enum.any?(result.entries, &(&1.id == record.id))
    assert result.semantic_available == true
  end

  test "record/1 updates an existing source record instead of duplicating it" do
    session = session_fixture()

    attrs = %{
      workspace_id: session.workspace_id,
      session_id: session.id,
      record_type: "decision",
      title: "Original decision",
      summary: "Original summary",
      source_type: "review",
      source_id: "review-123"
    }

    assert {:ok, original} = Memory.record(attrs)

    assert {:ok, updated} =
             Memory.record(
               Map.merge(attrs, %{
                 title: "Updated decision",
                 summary: "Updated summary",
                 body: "Updated body"
               })
             )

    assert updated.id == original.id
    assert updated.title == "Updated decision"

    result = Memory.search("Updated", workspace_id: session.workspace_id, source_id: "review-123")
    assert Enum.map(result.entries, & &1.id) == [original.id]
  end

  test "record/1 validates visibility and org sharing scope" do
    org = org_fixture()
    session = session_fixture()

    base = %{
      workspace_id: session.workspace_id,
      session_id: session.id,
      record_type: "decision",
      title: "Shared memory",
      summary: "Shared summary",
      source_type: "test",
      source_id: "shared-memory"
    }

    assert {:error, changeset} = Memory.record(Map.put(base, :visibility, "public"))
    assert %{visibility: ["is invalid"]} = errors_on(changeset)

    assert {:error, changeset} = Memory.record(Map.put(base, :visibility, "org"))
    assert %{shared_org_id: ["can't be blank"]} = errors_on(changeset)

    assert {:ok, record} =
             Memory.record(Map.merge(base, %{visibility: "org", shared_org_id: org.id}))

    assert record.visibility == "org"
    assert record.shared_org_id == org.id
  end

  test "archive_record/1 removes a memory hit from retrieval" do
    session = session_fixture()

    record =
      memory_record_fixture(%{
        session: session,
        title: "Archive me",
        summary: "This should disappear from search",
        body: "Nothing special."
      })

    assert Enum.any?(
             Memory.search("archive", session_id: session.id).entries,
             &(&1.id == record.id)
           )

    assert {:ok, archived} = Memory.archive_record(record.id)
    assert archived.archived_at

    refute Enum.any?(
             Memory.search("archive", session_id: session.id).entries,
             &(&1.id == record.id)
           )
  end

  test "sqlite search reranks with semantic similarity when embeddings are available" do
    session = session_fixture()

    sql_record =
      memory_record_fixture(%{
        session: session,
        title: "SQL lesson",
        summary: "Use parameterized sql queries everywhere",
        body: "Placeholders beat string concatenation."
      })

    _xss_record =
      memory_record_fixture(%{
        session: session,
        title: "XSS lesson",
        summary: "Avoid unsafe innerHTML in the browser",
        body: "Prefer safe DOM updates."
      })

    result =
      Memory.search("sql query placeholders",
        session_id: session.id,
        workspace_id: session.workspace_id
      )

    assert hd(result.entries).id == sql_record.id
    assert hd(result.entries).semantic_score > 0.0
  end

  test "pgvector store falls back cleanly when postgres vector search is unavailable" do
    refute Pgvector.available?()
    session = session_fixture()
    _record = memory_record_fixture(%{session: session, title: "Fallback memory"})

    result = Pgvector.search("fallback", session_id: session.id)
    assert Enum.any?(result.entries, &(&1.title == "Fallback memory"))
  end

  test "retention scheduler is opt-in and advertises findings preservation by default" do
    previous = Application.get_env(:controlkeel, :memory_retention)
    System.delete_env("CK_MEMORY_RETENTION_SCHEDULER")

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :memory_retention, previous)
      else
        Application.delete_env(:controlkeel, :memory_retention)
      end

      System.delete_env("CK_MEMORY_RETENTION_SCHEDULER")
    end)

    Application.delete_env(:controlkeel, :memory_retention)
    refute ControlKeel.Memory.RetentionScheduler.enabled?()

    policy = ControlKeel.Memory.RetentionScheduler.policy()
    assert policy.findings.enabled == false
    assert policy.findings.action == :preserve
    assert policy.memory.record_types == ~w(task checkpoint budget)

    Application.put_env(:controlkeel, :memory_retention, enabled: true, max_age_days: 30)
    assert ControlKeel.Memory.RetentionScheduler.enabled?()
    assert ControlKeel.Memory.RetentionScheduler.policy().memory.max_age_days == 30
  end

  test "archive_stale_records archives stale transient records but preserves recent and durable ones" do
    session = session_fixture()

    insert = fn type, source_id ->
      {:ok, record} =
        Memory.record(%{
          workspace_id: session.workspace_id,
          session_id: session.id,
          record_type: type,
          title: "#{type} #{source_id}",
          summary: "s",
          source_type: "test",
          source_id: source_id
        })

      record
    end

    stale_task = insert.("task", "stale-task")
    recent_task = insert.("task", "recent-task")
    old_proof = insert.("proof", "old-proof")

    # Backdate the stale task and the durable proof well past the retention cutoff.
    old =
      DateTime.utc_now() |> DateTime.add(-200 * 86_400, :second) |> DateTime.truncate(:second)

    Enum.each([stale_task, old_proof], fn record ->
      record |> Ecto.Changeset.change(%{inserted_at: old}) |> ControlKeel.Repo.update!()
    end)

    assert {:ok, %{archived: 1, ids: [archived_id]}} =
             Memory.archive_stale_records(max_age_days: 90)

    assert archived_id == stale_task.id
    # stale transient record archived; recent transient + durable (proof) preserved
    assert Memory.get_record(stale_task.id).archived_at != nil
    assert Memory.get_record(recent_task.id).archived_at == nil
    assert Memory.get_record(old_proof.id).archived_at == nil
  end
end
