defmodule ControlKeel.ProviderBrokerTest do
  use ExUnit.Case, async: false

  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProviderBroker

  @provider_envs ~w(ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY CONTROLKEEL_OLLAMA_BASE_URL OLLAMA_HOST)

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-provider-broker-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    home_dir = Path.join(tmp_dir, "home")
    project_root = Path.join(tmp_dir, "project")
    File.mkdir_p!(home_dir)
    File.mkdir_p!(project_root)

    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")
    previous_provider_envs = Enum.into(@provider_envs, %{}, &{&1, System.get_env(&1)})

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)

    Enum.each(@provider_envs, &System.delete_env/1)

    on_exit(fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)

      Enum.each(previous_provider_envs, fn {key, value} ->
        restore_env(key, value)
      end)

      File.rm_rf!(tmp_dir)
    end)

    %{home_dir: home_dir, project_root: project_root}
  end

  test "falls back to heuristic when no provider is configured", %{project_root: project_root} do
    status = ProviderBroker.status(project_root)

    assert status["selected_source"] == "heuristic"
    assert status["selected_provider"] == "heuristic"
    assert status["bootstrap"]["mode"] == "none"
    assert Enum.any?(status["provider_chain"], &(&1["source"] == "heuristic"))
  end

  test "user default profile beats ollama when both are available", %{project_root: project_root} do
    assert {:ok, _config} = ProviderBroker.set_key("openai", "sk-user-default")
    assert {:ok, _config} = ProviderBroker.set_default_source("openai")
    System.put_env("CONTROLKEEL_OLLAMA_BASE_URL", "http://127.0.0.1:11434")

    status = ProviderBroker.status(project_root)

    assert status["selected_source"] == "user_default_profile"
    assert status["selected_provider"] == "openai"
    assert Enum.at(status["fallback_chain"], 0) == "user_default_profile"
    assert "ollama" in status["fallback_chain"]
  end

  test "environment override beats stored profile for hosted providers", %{
    project_root: project_root
  } do
    assert {:ok, _config} = ProviderBroker.set_key("openai", "sk-stored")
    System.put_env("OPENAI_API_KEY", "sk-env")

    resolution = ProviderBroker.resolve_provider("openai", project_root)

    assert resolution.source == "user_default_profile"
    assert resolution.provider == "openai"
    assert resolution.config["api_key"] == "sk-env"
  end

  test "attached agent bridge wins before CK-owned user profiles", %{project_root: project_root} do
    assert {:ok, _config} = ProviderBroker.set_key("openai", "sk-user-default")
    assert {:ok, _config} = ProviderBroker.set_default_source("openai")
    System.put_env("ANTHROPIC_API_KEY", "sk-ant-bridge")

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "claude",
                 "attached_agents" => %{
                   "claude-code" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    status = ProviderBroker.status(project_root)

    assert status["selected_source"] == "agent_bridge"
    assert status["selected_provider"] == "anthropic"
    assert Enum.at(status["attached_agents"], 0)["provider_bridge_supported"] == true
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
