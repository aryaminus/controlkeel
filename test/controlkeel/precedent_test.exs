defmodule ControlKeel.PrecedentTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mission.Session
  alias ControlKeel.Precedent

  describe "workspace scoping guards" do
    test "for_rule_ids/for_rule_id return [] when workspace_id is nil" do
      # A nil workspace_id leaves the underlying Memory search unscoped, which
      # would surface dispositions across every workspace. Precedent must refuse.
      assert Precedent.for_rule_ids(["secret.aws_access_key"], workspace_id: nil) == []
      assert Precedent.for_rule_id("secret.aws_access_key", workspace_id: nil) == []
    end

    test "workspace_precedent returns [] when the session has no workspace_id" do
      assert Precedent.workspace_precedent(%Session{workspace_id: nil}) == []
    end
  end
end
