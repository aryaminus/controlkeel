defmodule ControlKeel.Skills.TargetResolver do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Skills.TargetFamily

  def resolve(project_root, requested_target \\ nil) do
    cond do
      is_binary(requested_target) and String.trim(requested_target) != "" ->
        normalize_target(requested_target)

      is_binary(project_root) and project_root != "" ->
        project_root
        |> binding_target()
        |> Kernel.||("open-standard")

      true ->
        "open-standard"
    end
  end

  def family(project_root, requested_target \\ nil) do
    resolve(project_root, requested_target)
    |> TargetFamily.family_for()
  end

  defp binding_target(project_root) do
    with {:ok, binding, _mode} <- ProjectBinding.read_effective(project_root),
         %{} = attached_agents <- Map.get(binding, "attached_agents"),
         {agent_id, _attrs} <- Enum.at(attached_agents, 0) do
      normalize_target(agent_id)
    else
      _ -> nil
    end
  end

  defp normalize_target(target) do
    normalized =
      target
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace("_", "-")

    case AgentIntegration.get(normalized) do
      %{} -> normalized
      _ -> normalized
    end
  end
end
