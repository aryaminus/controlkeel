defmodule ControlKeel.Cloud.Audit.ExportTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Audit.Export
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.MissionFixtures

  describe "build/1 scope validation" do
    test "returns :scope_required when neither workspace_id nor org_id is given" do
      assert {:error, :scope_required} = Export.build([])
    end

    test "returns :scope_conflict when both are given" do
      assert {:error, :scope_conflict} = Export.build(workspace_id: 1, org_id: 1)
    end

    test "returns :unknown_workspace for missing workspace" do
      assert {:error, :unknown_workspace} = Export.build(workspace_id: 999_999)
    end

    test "returns :unknown_org for missing org" do
      assert {:error, :unknown_org} = Export.build(org_id: 999_999)
    end
  end

  describe "build/1 workspace scope" do
    setup do
      {workspace, user, _org} = MissionFixtures.org_bound_workspace_fixture()
      session = MissionFixtures.session_fixture(%{workspace: workspace})
      finding = MissionFixtures.finding_fixture(%{session: session, severity: "high"})
      review = MissionFixtures.review_fixture(%{session: session, title: "Plan review"})
      {:ok, workspace: workspace, session: session, finding: finding, review: review, user: user}
    end

    test "captures findings and reviews", %{
      workspace: workspace,
      finding: finding,
      review: review
    } do
      {:ok, bundle} = Export.build(workspace_id: workspace.id)

      assert bundle["schema_version"] == "1"
      assert bundle["scope"]["type"] == "workspace"
      assert bundle["scope"]["id"] == workspace.id
      assert Enum.any?(bundle["findings"], &(&1["id"] == finding.id))
      assert Enum.any?(bundle["reviews"], &(&1["id"] == review.id))
      assert bundle["mcp_tool_calls"] == []
      assert bundle["cloud_run_packages"] == []
      assert bundle["received_telemetry_events"] == []
    end

    test "respects --since by filtering out older rows", %{workspace: workspace} do
      future = DateTime.utc_now() |> DateTime.add(86_400, :second)
      {:ok, bundle} = Export.build(workspace_id: workspace.id, since: future)
      assert bundle["findings"] == []
      assert bundle["reviews"] == []
    end

    test "captures run package lifecycle data", %{workspace: workspace, user: user} do
      {:ok, pkg, _token} =
        RuntimeContext.create_package(%{
          workspace_id: workspace.id,
          user_id: user.id,
          runtime_target: "devin",
          budget_cents_allocated: 100
        })

      {:ok, _} = RuntimeContext.transition_status(pkg, "completed")

      {:ok, bundle} = Export.build(workspace_id: workspace.id)

      assert [%{"runtime_target" => "devin", "status" => "completed"}] =
               bundle["cloud_run_packages"]
    end

    test "produces JSON-encodable output", %{workspace: workspace} do
      {:ok, bundle} = Export.build(workspace_id: workspace.id)
      assert is_binary(Jason.encode!(bundle))
    end
  end

  describe "build/1 org scope" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})

      ws_a =
        MissionFixtures.workspace_fixture(%{slug: "ws-a-#{System.unique_integer([:positive])}"})

      ws_b =
        MissionFixtures.workspace_fixture(%{slug: "ws-b-#{System.unique_integer([:positive])}"})

      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org.id)

      session_a = MissionFixtures.session_fixture(%{workspace: ws_a})
      session_b = MissionFixtures.session_fixture(%{workspace: ws_b})
      _ = MissionFixtures.finding_fixture(%{session: session_a, severity: "low"})
      _ = MissionFixtures.finding_fixture(%{session: session_b, severity: "medium"})

      {:ok, org: org, ws_a: ws_a, ws_b: ws_b}
    end

    test "aggregates findings across every workspace in the org", %{org: org} do
      {:ok, bundle} = Export.build(org_id: org.id)
      assert length(bundle["findings"]) == 2
      assert bundle["scope"] == %{"type" => "org", "id" => org.id}
    end

    test "received_telemetry_events section is populated only for org scope", %{org: org} do
      {:ok, bundle} = Export.build(org_id: org.id)
      # No received events were inserted, but the section exists and is a list
      assert is_list(bundle["received_telemetry_events"])
    end
  end
end
