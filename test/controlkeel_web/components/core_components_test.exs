defmodule ControlKeelWeb.CoreComponentsTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.CoreComponents

  describe "input_component select" do
    test "renders a select with prompt and options" do
      html =
        render_component(&CoreComponents.input_component/1,
          type: "select",
          label: "Risk tier",
          id: "filters-risk-tier",
          name: "filters[risk_tier]",
          value: "high",
          prompt: "All tiers",
          options: [{"Low", "low"}, {"High", "high"}]
        )

      assert html =~ ~s(<select)
      assert html =~ ~s(id="filters-risk-tier")
      assert html =~ ~s(name="filters[risk_tier]")
      assert html =~ ~s(<option value="">All tiers</option>)
      assert html =~ ~s(value="low")
      assert html =~ ~s(value="high")
      assert html =~ "selected"
    end

    test "marks the control invalid when errors are present" do
      html =
        render_component(&CoreComponents.input_component/1,
          type: "select",
          label: "Risk tier",
          id: "filters-risk-tier",
          name: "filters[risk_tier]",
          errors: ["must be set"],
          options: [{"Low", "low"}]
        )

      assert html =~ ~s(aria-invalid)
      assert html =~ "must be set"
    end
  end
end
