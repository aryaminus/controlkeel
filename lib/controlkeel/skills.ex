defmodule ControlKeel.Skills do
  @moduledoc false

  alias ControlKeel.Agent.ACPRegistry
  alias ControlKeel.Agent.Integration
  alias ControlKeel.Ops.Distribution
  alias ControlKeel.Skills.Exporter
  alias ControlKeel.Skills.Installer
  alias ControlKeel.Skills.Manifest
  alias ControlKeel.Skills.Pruner
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
  def agent_integrations, do: Integration.product_catalog() |> ACPRegistry.enrich_integrations()
  def release_targets, do: SkillTarget.release_targets()
  def install_channels, do: Distribution.install_channels()
  def current_install_channels, do: Distribution.current_install_channels()

  def export(target, project_root \\ File.cwd!(), opts \\ []) do
    Exporter.export(target, project_root, opts)
  end

  def export_manifests(project_root \\ File.cwd!()) do
    Manifest.list_export_manifests(project_root)
  end

  def install(target, project_root \\ File.cwd!(), opts \\ []) do
    Installer.install(target, project_root, opts)
  end

  def prune_duplicate_skills_preview(project_root \\ File.cwd!()),
    do: Pruner.preview(project_root)

  def prune_duplicate_skills(project_root \\ File.cwd!()),
    do: Pruner.prune(project_root)
end
