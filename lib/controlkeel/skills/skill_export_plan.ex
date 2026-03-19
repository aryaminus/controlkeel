defmodule ControlKeel.Skills.SkillExportPlan do
  @moduledoc false

  defstruct [:target, :output_dir, :scope, :writes, :instructions, :native_available]
end
