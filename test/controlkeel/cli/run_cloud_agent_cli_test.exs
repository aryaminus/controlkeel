defmodule ControlKeel.CLI.RunCloudAgentTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.MissionFixtures

  setup do
    {workspace, user, _org} = MissionFixtures.org_bound_workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session, title: "Add cloud feature"})
    {:ok, workspace: workspace, session: session, task: task, user: user}
  end

  describe "controlkeel run cloud-agent <task-id>" do
    test "creates a run package, prints token and metadata", %{
      task: task,
      user: user,
      workspace: workspace
    } do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options:
                     opts(
                       %{
                         runtime: "devin",
                         budget_cents: 500,
                         scopes: "mcp:access,context:read",
                         note: "investigate flaky test"
                       },
                       user
                     ),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Cloud run package created"))
      assert Enum.any?(lines, &(&1 =~ ~r/Package: pkg_[0-9A-Z]{26}/))
      assert Enum.any?(lines, &(&1 =~ "Runtime: devin"))
      assert Enum.any?(lines, &(&1 =~ "Budget allocated (cents): 500"))
      assert Enum.any?(lines, &(&1 =~ "Scopes: mcp:access,context:read"))
      assert Enum.any?(lines, &String.contains?(&1, "Callback token"))

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.task_id == task.id
      assert package.runtime_target == "devin"
      assert package.status == "pending"
      assert package.payload["task_title"] == "Add cloud feature"
      assert package.payload["note"] == "investigate flaky test"
      assert package.external_id =~ ~r/^pkg_[0-9A-Z]{26}$/
    end

    test "external_id is unique across packages and looks up via get_by_external_id", %{
      task: task,
      user: user
    } do
      assert {:ok, _lines1} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert {:ok, _lines2} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "open-swe", budget_cents: 0}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      packages = RuntimeContext.global_recent(limit: 10)
      ids = Enum.map(packages, & &1.external_id)
      assert length(Enum.uniq(ids)) == length(ids)

      first = hd(packages)
      assert RuntimeContext.get_by_external_id(first.external_id).id == first.id
      assert RuntimeContext.get_by_external_id("pkg_bogus") == nil
    end

    test "rejects unknown runtime with helpful message", %{task: task, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "not-a-real-runtime", budget_cents: 0}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "Unknown runtime"
      assert msg =~ "devin"
    end

    test "requires --runtime", %{task: task, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{budget_cents: 100}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "runtime"
    end

    test "rejects negative budget", %{task: task, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "open-swe", budget_cents: -10}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "non-negative integer"
    end

    test "rejects non-numeric task id", %{user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0}, user),
                   args: ["not-a-number"]
                 },
                 File.cwd!()
               )

      assert msg =~ "Invalid task-id"
    end

    test "returns 'Task not found' for unknown id", %{user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0}, user),
                   args: ["999999"]
                 },
                 File.cwd!()
               )

      assert msg =~ "Task not found"
    end
  end

  describe "CLI.parse/1" do
    test "parses run cloud-agent invocation" do
      assert {:ok, parsed} =
               CLI.parse([
                 "run",
                 "cloud-agent",
                 "42",
                 "--runtime",
                 "devin",
                 "--budget-cents",
                 "200"
               ])

      assert parsed.command == :run_cloud_agent
      assert parsed.args == ["42"]
      assert parsed.options[:runtime] == "devin"
      assert parsed.options[:budget_cents] == 200
    end

    test "parses git metadata overrides" do
      assert {:ok, parsed} =
               CLI.parse([
                 "run",
                 "cloud-agent",
                 "42",
                 "--runtime",
                 "devin",
                 "--budget-cents",
                 "0",
                 "--repo-url",
                 "git@github.com:acme/widget.git",
                 "--branch",
                 "feature/x",
                 "--commit-sha",
                 "abc123def4567890"
               ])

      assert parsed.options[:repo_url] == "git@github.com:acme/widget.git"
      assert parsed.options[:branch] == "feature/x"
      assert parsed.options[:commit_sha] == "abc123def4567890"
    end
  end

  describe "--dispatch flag (CK-CLOUD-DISPATCH-001)" do
    test "create-then-dispatch chains in one CLI invocation", %{
      task: task,
      user: user,
      workspace: workspace
    } do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0, dispatch: true}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Status: dispatched"))
      assert Enum.any?(lines, &(&1 =~ "Dispatched via: manual"))

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.status == "dispatched"
      assert package.dispatched_at
      assert get_in(package.payload, ["dispatch_metadata", "mode"]) == "manual"
    end

    test "default (no --dispatch) leaves package pending", %{
      task: task,
      user: user,
      workspace: workspace
    } do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Status: pending"))
      refute Enum.any?(lines, &(&1 =~ "Dispatched via"))

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.status == "pending"
    end
  end

  describe "git metadata capture (CK-CLOUD-PAYLOAD-001)" do
    test "captures repo/branch/commit_sha from a real git repo", %{
      task: task,
      workspace: workspace,
      user: user
    } do
      tmp = make_git_repo()

      assert {:ok, _lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0, project_root: tmp}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 tmp
               )

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.branch in ["main", "master"]
      assert is_binary(package.commit_sha)
      assert String.match?(package.commit_sha, ~r/^[0-9a-f]{40}$/)
      assert package.repo_url =~ "example.com"
    end

    test "leaves git fields nil when project_root is not a git repo", %{
      task: task,
      workspace: workspace,
      user: user
    } do
      tmp = Path.join(System.tmp_dir!(), "ck-no-git-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      assert {:ok, _lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: opts(%{runtime: "devin", budget_cents: 0, project_root: tmp}, user),
                   args: [Integer.to_string(task.id)]
                 },
                 tmp
               )

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.repo_url == nil
      assert package.branch == nil
      assert package.commit_sha == nil
    end

    test "explicit CLI overrides win over git", %{task: task, user: user, workspace: workspace} do
      tmp = make_git_repo()

      assert {:ok, _lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options:
                     opts(
                       %{
                         runtime: "devin",
                         budget_cents: 0,
                         project_root: tmp,
                         repo_url: "git@github.com:acme/override.git",
                         branch: "release-2.0",
                         commit_sha: "1234567"
                       },
                       user
                     ),
                   args: [Integer.to_string(task.id)]
                 },
                 tmp
               )

      [package] = RuntimeContext.list_for_workspace(workspace.id)
      assert package.repo_url == "git@github.com:acme/override.git"
      assert package.branch == "release-2.0"
      assert package.commit_sha == "1234567"
    end

    test "rejects malformed commit_sha", %{task: task, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options:
                     opts(
                       %{
                         runtime: "devin",
                         budget_cents: 0,
                         commit_sha: "not-a-sha"
                       },
                       user
                     ),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      assert msg =~ "commit_sha"
    end
  end

  # Cloud execution fails closed without an authorized user (#269), so every
  # CLI invocation in this file runs as the org owner that setup created.
  defp opts(map, user), do: Map.put_new(map, :user_id, user.id)

  defp make_git_repo do
    suffix =
      :crypto.strong_rand_bytes(8)
      |> Base.url_encode64(padding: false)

    tmp =
      Path.join(
        System.tmp_dir!(),
        "ck-git-#{System.unique_integer([:positive, :monotonic])}-#{suffix}"
      )

    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["init", "-q", "-b", "main"], cd: tmp, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["config", "user.email", "test@example.com"],
        cd: tmp,
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("git", ["config", "user.name", "test"], cd: tmp, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["remote", "add", "origin", "https://example.com/acme/widget.git"],
        cd: tmp,
        stderr_to_stdout: true
      )

    File.write!(Path.join(tmp, "README"), "hi\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: tmp, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-q", "-m", "init"], cd: tmp, stderr_to_stdout: true)

    tmp
  end
end
