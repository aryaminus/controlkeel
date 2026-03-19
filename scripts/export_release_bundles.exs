for target <- ControlKeel.Skills.release_targets() do
  {:ok, plan} =
    ControlKeel.Skills.export(
      target,
      File.cwd!(),
      scope: "export",
      portable_project_root: true
    )

  IO.puts("Exported #{plan.target} bundle to #{plan.output_dir}")
end
