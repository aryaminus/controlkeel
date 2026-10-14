defmodule ControlKeel.Cloud.RuntimeDispatcherTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.RuntimeDispatcher
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  defmodule StubOkDispatcher do
    @behaviour ControlKeel.Cloud.RuntimeDispatcher

    @impl true
    def dispatch(_package, opts) do
      {:ok,
       %{
         "mode" => "stub_ok",
         "raw_token_seen?" => is_binary(Keyword.get(opts, :raw_token)),
         "ticket_id" => "tkt_42"
       }}
    end
  end

  defmodule StubFailingDispatcher do
    @behaviour ControlKeel.Cloud.RuntimeDispatcher

    @impl true
    def dispatch(_package, _opts), do: {:error, :stub_explosion}
  end

  setup do
    {workspace, user, _org} = MissionFixtures.org_bound_workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session})

    previous = Application.get_env(:controlkeel, :cloud_dispatchers, %{})
    previous_mode = Application.get_env(:controlkeel, :runtime_mode)
    previous_env_mode = System.get_env("CONTROLKEEL_RUNTIME_MODE")

    Application.put_env(:controlkeel, :runtime_mode, :local)
    System.delete_env("CONTROLKEEL_RUNTIME_MODE")

    on_exit(fn ->
      Application.put_env(:controlkeel, :cloud_dispatchers, previous)

      if previous_mode,
        do: Application.put_env(:controlkeel, :runtime_mode, previous_mode),
        else: Application.delete_env(:controlkeel, :runtime_mode)

      if previous_env_mode,
        do: System.put_env("CONTROLKEEL_RUNTIME_MODE", previous_env_mode),
        else: System.delete_env("CONTROLKEEL_RUNTIME_MODE")
    end)

    {:ok, workspace: workspace, session: session, task: task, user: user}
  end

  describe "RuntimeDispatcher.for_runtime/1" do
    test "defaults to Manual when no config is set" do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})
      assert RuntimeDispatcher.for_runtime("devin") == RuntimeDispatcher.Manual
    end

    test "respects the configured override" do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "devin" => StubOkDispatcher
      })

      assert RuntimeDispatcher.for_runtime("devin") == StubOkDispatcher
      # Other runtimes still fall back locally
      assert RuntimeDispatcher.for_runtime("open-swe") == RuntimeDispatcher.Manual
    end

    test "requires configured dispatcher in cloud mode" do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})

      assert RuntimeDispatcher.for_runtime("devin") == RuntimeDispatcher.RemoteRequired
    end

    test "requires configured dispatcher in self-hosted mode" do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})

      assert RuntimeDispatcher.for_runtime("devin") == RuntimeDispatcher.RemoteRequired
    end
  end

  describe "RuntimeDispatcher.Manual.dispatch/2" do
    test "records the manual handoff intent", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      {:ok, package, _token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:ok, meta} = RuntimeDispatcher.Manual.dispatch(package, [])
      assert meta["mode"] == "manual"
      assert meta["runtime_target"] == "devin"
      assert is_binary(meta["note"])
    end
  end

  describe "RuntimeContext.dispatch_package/3" do
    test "transitions pending → dispatched and stores metadata", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "devin" => StubOkDispatcher
      })

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert package.status == "pending"

      assert {:ok, dispatched} = RuntimeContext.dispatch_package(package, raw_token)
      assert dispatched.status == "dispatched"
      assert dispatched.dispatched_at
      assert get_in(dispatched.payload, ["dispatch_metadata", "ticket_id"]) == "tkt_42"
      assert get_in(dispatched.payload, ["dispatch_metadata", "raw_token_seen?"]) == true
    end

    test "transitions to failed and records error_summary when dispatcher errors", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "open-swe" => StubFailingDispatcher
      })

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "open-swe",
          budget_cents_allocated: 0
        })

      assert {:error, :stub_explosion} = RuntimeContext.dispatch_package(package, raw_token)

      reloaded = Repo.get!(RunPackage, package.id)
      assert reloaded.status == "failed"
      assert reloaded.error_summary =~ "stub_explosion"
      assert reloaded.completed_at
    end

    test "remote mode without configured dispatcher fails closed instead of manual handoff", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:error, {:remote_dispatcher_required, details}} =
               RuntimeContext.dispatch_package(package, raw_token)

      assert details.runtime_target == "devin"
      assert details.runtime_mode == :cloud

      reloaded = Repo.get!(RunPackage, package.id)
      assert reloaded.status == "failed"
      assert reloaded.error_summary =~ "remote_dispatcher_required"
    end

    test "remote mode uses configured dispatcher when present", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)

      Application.put_env(:controlkeel, :cloud_dispatchers, %{
        "devin" => StubOkDispatcher
      })

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:ok, dispatched} = RuntimeContext.dispatch_package(package, raw_token)
      assert dispatched.status == "dispatched"
      assert get_in(dispatched.payload, ["dispatch_metadata", "mode"]) == "stub_ok"
    end

    test "Manual default still produces a clean dispatched transition in local mode", %{
      workspace: workspace,
      user: user,
      session: session,
      task: task
    } do
      Application.put_env(:controlkeel, :cloud_dispatchers, %{})

      {:ok, package, raw_token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 0
        })

      assert {:ok, dispatched} = RuntimeContext.dispatch_package(package, raw_token)
      assert dispatched.status == "dispatched"
      assert get_in(dispatched.payload, ["dispatch_metadata", "mode"]) == "manual"
    end
  end
end
