defmodule ControlKeel.Deployment.AdvisorTest do
  use ControlKeel.DataCase

  alias ControlKeel.Deployment.Advisor

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-advisor-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "analyzes a Phoenix project", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      defp deps, do: [{:phoenix, "~> 1.7"}]
    end
    """)

    File.mkdir_p!(Path.join(tmp_dir, "config"))
    File.write!(Path.join(tmp_dir, "config/config.exs"), "use Mix.Config")

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :phoenix
    assert length(result.platforms) > 0
    assert result.monthly_cost_range.low == 0
    assert result.monthly_cost_range.high == 50
    assert length(result.generators) == 4

    [dockerfile, compose, ci, env] = result.generators
    assert dockerfile.filename == "Dockerfile"
    assert compose.filename == "docker-compose.yml"
    assert ci.filename == ".github/workflows/ci.yml"
    assert env.filename == ".env.example"

    assert dockerfile.content =~ "hexpm/elixir"
    assert compose.content =~ "postgres"
    assert ci.content =~ "setup-beam"
    assert env.content =~ "SECRET_KEY_BASE"
  end

  test "analyzes a React project", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "package.json"), ~s({"dependencies": {"react": "^18"}}))

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :react
    assert result.monthly_cost_range.high == 20

    [dockerfile | _] = result.generators
    assert dockerfile.content =~ "node:20"
  end

  test "analyzes a Rails project", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "Gemfile"), """
    source 'https://rubygems.org'
    gem 'rails', '~> 7.0'
    """)

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :rails
    assert result.monthly_cost_range.low == 7
  end

  test "analyzes a Node project", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "package.json"), ~s({"dependencies": {"express": "^4"}}))

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :node
  end

  test "analyzes a Python project", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "requirements.txt"), "Flask==3.0.0\nWerkzeug==3.0.0")

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :python
  end

  test "falls back to static for unknown projects", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "index.html"), "<html></html>")

    assert {:ok, result} = Advisor.analyze(tmp_dir)
    assert result.stack == :static
    assert result.monthly_cost_range.high == 0
  end

  test "generate_files writes files to disk", %{tmp_dir: tmp_dir} do
    generators = [
      %{name: "Test", filename: "test_output.txt", content: "hello world"}
    ]

    assert {:ok, results} = Advisor.generate_files(tmp_dir, generators)
    [{:ok, "Test", path, _content, :written}] = results
    assert File.read!(path) == "hello world"
  end

  test "generate_files in dry_run mode skips writing", %{tmp_dir: tmp_dir} do
    generators = [
      %{name: "Test", filename: "dry_run_test.txt", content: "should not appear"}
    ]

    assert {:ok, results} = Advisor.generate_files(tmp_dir, generators, dry_run: true)
    [{:ok, "Test", _path, _content, :skipped}] = results
    refute File.exists?(Path.join(tmp_dir, "dry_run_test.txt"))
  end

  test "dns_ssl_guide returns DNS and SSL information" do
    guide = Advisor.dns_ssl_guide(:phoenix)

    assert is_list(guide.dns_setup)
    assert is_list(guide.ssl_setup)
    assert length(guide.domain_registrars) > 0
    assert is_map(guide.free_ssl)
  end

  test "db_migration_guide returns migration steps" do
    guide = Advisor.db_migration_guide(:phoenix)

    assert guide.stack == :phoenix
    assert is_list(guide.steps)
    assert guide.steps |> Enum.any?(&String.contains?(&1, "ecto"))
    assert is_binary(guide.rollback)
    assert is_binary(guide.backup_before)
  end

  test "scaling_guide returns scaling recommendations" do
    guide = Advisor.scaling_guide(:phoenix)

    assert guide.stack == :phoenix
    assert is_map(guide.vertical_scaling)
    assert length(guide.vertical_scaling.tiers) == 3
    assert is_binary(guide.horizontal_scaling)
    assert is_binary(guide.database_scaling)
    assert length(guide.caching) > 0
    assert length(guide.monitoring) > 0
    assert length(guide.concurrent_users_guide) > 0
  end

  test "Phoenix platforms prioritize Fly.io", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule MyApp.MixProject do
      use Mix.Project
      defp deps, do: [{:phoenix, "~> 1.7"}]
    end
    """)

    {:ok, result} = Advisor.analyze(tmp_dir)
    [first | _] = result.platforms
    assert first.id == :fly_io
  end
end
