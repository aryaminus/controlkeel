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
    assert get_in(status, ["selected_trust_profile", "trust_boundary"]) == "no_provider_selected"
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
    assert get_in(status, ["selected_trust_profile", "trust_boundary"]) == "direct_provider"
    assert get_in(status, ["selected_trust_profile", "intermediary_risk"]) == "low"

    assert Enum.at(status["fallback_chain"], 0) == "user_default_profile"
    assert "ollama" in status["fallback_chain"]
  end

  test "custom OpenAI-compatible base URL counts as configured without an API key", %{
    project_root: project_root
  } do
    assert {:ok, _config} = ProviderBroker.set_base_url("openai", "http://127.0.0.1:1234/v1")
    assert {:ok, _config} = ProviderBroker.set_model("openai", "local-model")
    assert {:ok, _config} = ProviderBroker.set_default_source("openai")

    status = ProviderBroker.status(project_root)

    assert status["selected_source"] == "user_default_profile"
    assert status["selected_provider"] == "openai"

    assert get_in(status, ["selected_trust_profile", "trust_boundary"]) ==
             "openai_compatible_gateway"

    openai_profile = Enum.find(status["profiles"], &(&1["provider"] == "openai"))
    assert openai_profile["configured"] == true
    assert openai_profile["base_url"] == "http://127.0.0.1:1234/v1"
    assert get_in(openai_profile, ["trust_hint", "intermediary_risk"]) == "high"
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

    assert get_in(status, ["selected_trust_profile", "trust_boundary"]) ==
             "host_managed_agent_bridge"

    assert Enum.at(status["attached_agents"], 0)["provider_bridge_supported"] == true
  end

  test "config-reference bridge can reuse attached Hermes provider metadata", %{
    project_root: project_root,
    home_dir: home_dir
  } do
    hermes_dir = Path.join(home_dir, ".hermes")
    File.mkdir_p!(hermes_dir)
    File.write!(Path.join(hermes_dir, "config.yaml"), "provider: openai\nmodel: gpt-5.4-mini\n")
    System.put_env("OPENAI_API_KEY", "sk-hermes-openai")

    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "hermes-agent",
                 "attached_agents" => %{
                   "hermes-agent" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    status = ProviderBroker.status(project_root)

    assert status["selected_source"] == "agent_bridge"
    assert status["selected_provider"] == "openai"
    assert status["selected_auth_mode"] == "config_reference"

    attached = Enum.find(status["attached_agents"], &(&1["id"] == "hermes-agent"))
    assert attached["auth_mode"] == "config_reference"
    assert attached["auth_owner"] == "agent"
  end

  test "runtime-backed agents expose host-owned auth hints even without CK keys", %{
    project_root: project_root
  } do
    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "opencode",
                 "attached_agents" => %{
                   "opencode" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    status = ProviderBroker.status(project_root)

    attached = Enum.find(status["attached_agents"], &(&1["id"] == "opencode"))
    hint = Enum.find(status["runtime_hints"], &(&1["agent_id"] == "opencode"))

    assert attached["runtime_transport"] == "opencode_sdk"
    assert attached["runtime_auth_owner"] == "agent"
    assert attached["runtime_provider_hint"]["source"] == "agent_runtime"
    assert is_map(attached["runtime_capabilities"])
    assert attached["runtime_capabilities"][:policy_gate] == true
    assert hint["transport"] == "opencode_sdk"
    assert hint["hint"]["auth_owner"] == "agent"
  end

  test "codex app-server surfaces its dedicated runtime transport", %{project_root: project_root} do
    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "codex-app-server",
                 "attached_agents" => %{
                   "codex-app-server" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    status = ProviderBroker.status(project_root)

    attached = Enum.find(status["attached_agents"], &(&1["id"] == "codex-app-server"))
    hint = Enum.find(status["runtime_hints"], &(&1["agent_id"] == "codex-app-server"))

    assert attached["runtime_transport"] == "codex_app_server_json_rpc"
    assert attached["runtime_review_transport"] == "app_server_review"
    assert attached["runtime_provider_hint"]["source"] == "agent_runtime"
    assert is_map(attached["runtime_capabilities"])
    assert hint["transport"] == "codex_app_server_json_rpc"
  end

  test "t3code surfaces dedicated runtime transport and provider-neutral hints", %{
    project_root: project_root
  } do
    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "t3code",
                 "attached_agents" => %{
                   "t3code" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    status = ProviderBroker.status(project_root)

    attached = Enum.find(status["attached_agents"], &(&1["id"] == "t3code"))
    hint = Enum.find(status["runtime_hints"], &(&1["agent_id"] == "t3code"))

    assert attached["runtime_transport"] == "t3code_provider_runtime"
    assert attached["runtime_review_transport"] == "orchestration_domain_event"
    assert attached["runtime_provider_hint"]["source"] == "agent_runtime"
    assert attached["runtime_provider_hint"]["provider"] == "provider_neutral"
    assert attached["runtime_capabilities"][:policy_gate] == true
    assert attached["runtime_capabilities"][:tool_approval] == true
    assert attached["runtime_capabilities"][:deterministic_event_ids] == true
    assert hint["transport"] == "t3code_provider_runtime"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
