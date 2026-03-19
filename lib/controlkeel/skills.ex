defmodule ControlKeel.Skills do
  @moduledoc false

  alias ControlKeel.AgentIntegration
  alias ControlKeel.Distribution
  alias ControlKeel.Skills.Exporter
  alias ControlKeel.Skills.Installer
  alias ControlKeel.Skills.Registry
  alias ControlKeel.Skills.SkillTarget

  def catalog(project_root \\ nil, opts \\ []), do: Registry.catalog(project_root, opts)

  def analyze(project_root \\ nil, opts \\ []), do: Registry.analyze(project_root, opts)

  def validate(project_root \\ nil, opts \\ []) do
    analysis = analyze(project_root, opts)

    warnings = Enum.filter(analysis.diagnostics, &(&1.level == "warn"))
    errors = Enum.filter(analysis.diagnostics, &(&1.level == "error"))

    Map.merge(analysis, %{
      valid?: errors == [],
      total: length(analysis.skills),
      warning_count: length(warnings),
      error_count: length(errors)
    })
  end

  def targets, do: SkillTarget.catalog()
  def agent_integrations, do: AgentIntegration.catalog()
  def release_targets, do: SkillTarget.release_targets()
  def install_channels, do: Distribution.install_channels()
  def current_install_channels, do: Distribution.current_install_channels()

  def export(target, project_root \\ File.cwd!(), opts \\ []) do
    Exporter.export(target, project_root, opts)
  end

  def install(target, project_root \\ File.cwd!(), opts \\ []) do
    Installer.install(target, project_root, opts)
  end
end
