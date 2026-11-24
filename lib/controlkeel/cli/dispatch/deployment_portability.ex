defmodule ControlKeel.CLI.Dispatch.DeploymentPortability do
  @moduledoc false

  alias ControlKeel.Ops.DeploymentAdvisor, as: Advisor
  alias ControlKeel.Ops.HostingCost
  alias ControlKeel.CLI.SetupAdvisor
  alias ControlKeel.Skills
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :runtime_export, args: ["devin"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("devin-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Devin runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Devin runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: [runtime_id]}, _project_root) do
    {:error, "Unknown runtime export target: #{runtime_id}"}
  end

  def run_command(%{command: :deploy_analyze, options: options}, project_root) do
    root = options[:project_root] || project_root

    case Advisor.analyze(root) do
      {:ok, result} ->
        platform_lines =
          Enum.map_join(result.platforms, "\n", fn p ->
            "  - " <> p.name <> " (" <> p.url <> ")"
          end)

        generator_lines =
          Enum.map_join(result.generators, "\n", fn g ->
            "  - " <> g.name <> " (" <> g.filename <> ")"
          end)

        lines =
          ["Stack: " <> to_string(result.stack), ""] ++
            ["Compatible platforms:", platform_lines, ""] ++
            [
              "Monthly cost estimate: $" <>
                to_string(result.monthly_cost_range.low) <>
                " - $" <> to_string(result.monthly_cost_range.high),
              ""
            ] ++
            ["Generated files:", generator_lines]

        {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_cost, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "static", deployment_stacks(), "stack"),
         {:ok, tier} <- parse_atom_option(options[:tier] || "free", hosting_tiers(), "tier"),
         {:ok, db_tier} <-
           parse_atom_option(options[:db_tier] || "managed_small", database_tiers(), "db_tier") do
      needs_db = options[:needs_db] || false
      bandwidth = options[:bandwidth] || 10
      storage = options[:storage] || 1

      case HostingCost.estimate(
             stack: stack,
             tier: tier,
             needs_db: needs_db,
             db_tier: db_tier,
             expected_bandwidth_gb: bandwidth,
             expected_storage_gb: storage
           ) do
        {:ok, estimates} ->
          lines =
            Enum.map(estimates, fn e ->
              fit = if e.fits_stack, do: "check", else: " "

              "$" <>
                to_string(Float.round(e.total_monthly_usd, 2)) <>
                " [#{fit}] " <> e.name <> " - " <> e.notes
            end)

          {:ok, ["Hosting cost estimates (stack: #{stack}):", "" | lines]}
      end
    end
  end

  def run_command(%{command: :deploy_dns, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.dns_ssl_guide(stack)

      lines =
        ["DNS Setup for #{stack}:", ""] ++
          Enum.map(guide.dns_setup, &("  " <> &1)) ++
          ["", "SSL Setup:", ""] ++
          Enum.map(guide.ssl_setup, &("  " <> &1))

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_migration, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.db_migration_guide(stack)

      lines =
        ["Database Migration Guide for #{stack}:", ""] ++
          Enum.map(guide.steps, &("  " <> &1)) ++
          ["", "Rollback: #{guide.rollback}", "Backup: #{guide.backup_before}"]

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_scaling, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.scaling_guide(stack)

      lines = ["Scaling Guide for #{stack}:", ""]

      lines =
        lines ++
          ["Vertical Scaling:", "  #{guide.vertical_scaling.description}"] ++
          Enum.map(guide.vertical_scaling.tiers, fn t ->
            "  #{t.users} users: #{t.tier} - #{t.cost}"
          end) ++
          [
            "",
            "Horizontal: #{guide.horizontal_scaling}",
            "",
            "Database: #{guide.database_scaling}"
          ]

      {:ok, lines}
    end
  end
end
