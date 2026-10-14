defmodule ControlKeel.CLI.GovernGithubTest do
  @moduledoc """
  CLI surface for CK-CLOUD-GIT-001: `controlkeel govern bind|unbind|list github`.
  """

  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Mission
  alias ControlKeel.MissionFixtures

  setup do
    {workspace, user, _org} = MissionFixtures.org_bound_workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session, title: "Build feature"})
    {:ok, workspace: workspace, session: session, task: task, user: user}
  end

  describe "controlkeel govern bind github" do
    test "binds a repo to the workspace and prints summary", %{workspace: ws, user: user} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :govern_bind_github,
                   options:
                     Map.put_new(
                       %{
                         workspace_id: ws.id,
                         owner: "acme",
                         repo: "widget",
                         default_branch: "main",
                         installation_id: "12345"
                       },
                       :user_id,
                       user.id
                     ),
                   args: []
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Bound GitHub repository"))
      assert Enum.any?(lines, &(&1 =~ "Repo: acme/widget"))
      assert Enum.any?(lines, &(&1 =~ "https://github.com/acme/widget"))
      assert Enum.any?(lines, &(&1 =~ "Default branch: main"))
      assert Enum.any?(lines, &(&1 =~ "Installation: 12345"))

      assert [binding] = Mission.list_github_repos(ws.id)
      assert binding.installation_id == "12345"
    end

    test "errors when required flags are missing", %{workspace: ws, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :govern_bind_github,
                   options: Map.put_new(%{workspace_id: ws.id, owner: "acme"}, :user_id, user.id),
                   args: []
                 },
                 File.cwd!()
               )

      assert msg =~ "--repo"
    end

    test "surfaces changeset errors on duplicate bind", %{workspace: ws, user: user} do
      Mission.bind_github_repo(ws.id, "acme", "widget")

      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :govern_bind_github,
                   options:
                     Map.put_new(
                       %{workspace_id: ws.id, owner: "acme", repo: "widget"},
                       :user_id,
                       user.id
                     ),
                   args: []
                 },
                 File.cwd!()
               )

      assert msg =~ "Failed to bind"
    end
  end

  describe "controlkeel govern unbind github" do
    test "removes the binding", %{workspace: ws, user: user} do
      Mission.bind_github_repo(ws.id, "acme", "widget")

      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :govern_unbind_github,
                   options:
                     Map.put_new(
                       %{workspace_id: ws.id, owner: "acme", repo: "widget"},
                       :user_id,
                       user.id
                     ),
                   args: []
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Unbound acme/widget"))
      assert Mission.list_github_repos(ws.id) == []
    end

    test "errors when binding does not exist", %{workspace: ws, user: user} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :govern_unbind_github,
                   options:
                     Map.put_new(
                       %{workspace_id: ws.id, owner: "acme", repo: "absent"},
                       :user_id,
                       user.id
                     ),
                   args: []
                 },
                 File.cwd!()
               )

      assert msg =~ "No binding found"
    end
  end

  describe "controlkeel govern list github" do
    test "lists bound repos", %{workspace: ws, user: user} do
      Mission.bind_github_repo(ws.id, "acme", "widget", default_branch: "trunk")
      Mission.bind_github_repo(ws.id, "acme", "gadget")

      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :govern_list_github,
                   options: Map.put_new(%{workspace_id: ws.id}, :user_id, user.id),
                   args: []
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "acme/widget"))
      assert Enum.any?(lines, &(&1 =~ "(default branch: trunk)"))
      assert Enum.any?(lines, &(&1 =~ "acme/gadget"))
    end

    test "reports empty state when nothing is bound", %{workspace: ws, user: user} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :govern_list_github,
                   options: Map.put_new(%{workspace_id: ws.id}, :user_id, user.id),
                   args: []
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "No GitHub repos bound"))
    end
  end

  describe "cloud payload propagation" do
    test "run cloud-agent payload includes bound github repos", %{
      workspace: ws,
      task: task,
      user: user
    } do
      Mission.bind_github_repo(ws.id, "acme", "widget", default_branch: "main")
      Mission.bind_github_repo(ws.id, "acme", "gadget", installation_id: "9999")

      assert {:ok, _lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: Map.put_new(%{runtime: "devin", budget_cents: 0}, :user_id, user.id),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      [package] = RuntimeContext.list_for_workspace(ws.id)
      repos = package.payload["github_repos"]
      assert is_list(repos)
      assert length(repos) == 2

      widget = Enum.find(repos, &(&1["repo"] == "widget"))
      assert widget["owner"] == "acme"
      assert widget["default_branch"] == "main"
      assert widget["url"] == "https://github.com/acme/widget"
      refute Map.has_key?(widget, "installation_id")

      gadget = Enum.find(repos, &(&1["repo"] == "gadget"))
      assert gadget["installation_id"] == "9999"
    end

    test "payload omits github_repos key when nothing is bound", %{
      workspace: ws,
      task: task,
      user: user
    } do
      assert {:ok, _lines} =
               CLI.run_command(
                 %{
                   command: :run_cloud_agent,
                   options: Map.put_new(%{runtime: "devin", budget_cents: 0}, :user_id, user.id),
                   args: [Integer.to_string(task.id)]
                 },
                 File.cwd!()
               )

      [package] = RuntimeContext.list_for_workspace(ws.id)
      refute Map.has_key?(package.payload, "github_repos")
    end
  end
end
