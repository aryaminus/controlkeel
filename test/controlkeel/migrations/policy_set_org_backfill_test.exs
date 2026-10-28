defmodule ControlKeel.Repo.Migrations.BackfillPolicySetOrgOwnershipTest do
  use ExUnit.Case, async: true

  # The migration's decision logic is pure; exercise it directly rather than
  # through the migrator (the test DB is migrated empty, where the backfill
  # is a no-op by design). The DB wiring runs on every `mix ecto.migrate`.

  alias ControlKeel.Repo.Migrations.BackfillPolicySetOrgOwnership, as: Migration

  describe "resolve_org_id/3" do
    test "a unique assignment-hint org wins over everything" do
      assert {:hint_org, 7} = Migration.resolve_org_id([7], [3, 7], 99)
    end

    test "ambiguous hints (two orgs) fall through to the sole org" do
      assert {:sole_org, 4} = Migration.resolve_org_id([4, 9], [4], 99)
    end

    test "no hint adopts a sole org" do
      assert {:sole_org, 4} = Migration.resolve_org_id([], [4], 99)
    end

    test "multi-org DB without a hint defaults to the oldest org" do
      assert {:oldest_org, 1} = Migration.resolve_org_id([], [1, 5, 8], 99)
    end

    test "zero-org DB adopts the created default org" do
      assert {:default_org, 99} = Migration.resolve_org_id([], [], 99)
    end

    test "hint orgs are compared deduplicated" do
      # Two assignment rows in the same org are one unique hint, not an
      # ambiguity.
      assert {:hint_org, 7} = Migration.resolve_org_id([7, 7], [3, 7], 99)
    end
  end

  describe "proceed_answer?/1" do
    test "empty input (enter / non-interactive eof) proceeds by default" do
      assert Migration.proceed_answer?("")
      assert Migration.proceed_answer?("   ")
      assert Migration.proceed_answer?(:eof)
      assert Migration.proceed_answer?(nil)
    end

    test "y and yes proceed case-insensitively" do
      assert Migration.proceed_answer?("y")
      assert Migration.proceed_answer?("Y")
      assert Migration.proceed_answer?("yes\n")
    end

    test "anything else aborts" do
      refute Migration.proceed_answer?("n")
      refute Migration.proceed_answer?("N")
      refute Migration.proceed_answer?("no")
      refute Migration.proceed_answer?("later")
    end
  end

  describe "default_org_attrs/0" do
    test "uses the reserved local-mode default org so boot reuses it" do
      # Must match ControlKeel.Bootstrap.LocalDefaults' reserved slug/name so
      # the boot seed finds this org instead of creating a second one.
      assert %{name: "Default Organization", slug: "default-organization", status: "active"} =
               Migration.default_org_attrs()
    end
  end
end
