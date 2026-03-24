defmodule ControlKeel.RuntimePaths do
  @moduledoc false

  def user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  def config_dir do
    Path.join(user_home(), ".controlkeel")
  end

  def config_path do
    Path.join(config_dir(), "config.json")
  end

  def cache_dir do
    Path.join(config_dir(), "cache")
  end

  def ephemeral_bindings_dir do
    Path.join(cache_dir(), "bindings")
  end

  def ephemeral_binding_path(project_root) do
    root = Path.expand(project_root)

    digest =
      :crypto.hash(:sha256, root)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    Path.join(ephemeral_bindings_dir(), "#{digest}.json")
  end
end
