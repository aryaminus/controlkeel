defmodule ControlKeel.Scanner.AdvisoryTest do
  use ExUnit.Case, async: false

  alias ControlKeel.ProjectBinding
  alias ControlKeel.Scanner.Advisory

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-advisory-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    home_dir = Path.join(tmp_dir, "home")
    project_root = Path.join(tmp_dir, "project")
    File.mkdir_p!(home_dir)
    File.mkdir_p!(project_root)

    previous_home = System.get_env("HOME")
    previous_ck_home = System.get_env("CONTROLKEEL_HOME")

    previous_provider_envs = %{
      "ANTHROPIC_API_KEY" => System.get_env("ANTHROPIC_API_KEY"),
      "OPENAI_API_KEY" => System.get_env("OPENAI_API_KEY"),
      "OPENROUTER_API_KEY" => System.get_env("OPENROUTER_API_KEY"),
      "CONTROLKEEL_OLLAMA_BASE_URL" => System.get_env("CONTROLKEEL_OLLAMA_BASE_URL"),
      "OLLAMA_HOST" => System.get_env("OLLAMA_HOST")
    }

    System.put_env("HOME", home_dir)
    System.put_env("CONTROLKEEL_HOME", home_dir)

    Enum.each(Map.keys(previous_provider_envs), &System.delete_env/1)

    on_exit(fn ->
      restore_env("HOME", previous_home)
      restore_env("CONTROLKEEL_HOME", previous_ck_home)

      Enum.each(previous_provider_envs, fn {key, value} ->
        restore_env(key, value)
      end)

      File.rm_rf!(tmp_dir)
    end)

    %{project_root: project_root}
  end

  test "reports a plain skipped-no-provider advisory when no runtime hint exists", %{
    project_root: project_root
  } do
    advisory =
      Advisory.advisory_status(%{"content" => String.duplicate("a", 40)}, [], project_root)

    assert advisory.status == "skipped_no_provider"
    assert advisory.detail == "No LLM provider configured; pattern scanners completed."
  end

  test "mentions host-managed runtime hints for codex-backed advisory skips", %{
    project_root: project_root
  } do
    assert {:ok, _binding} =
             ProjectBinding.write(
               %{
                 "workspace_id" => 1,
                 "session_id" => 1,
                 "agent" => "codex-cli",
                 "attached_agents" => %{
                   "codex-cli" => %{
                     "attached_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                   }
                 }
               },
               project_root
             )

    advisory =
      Advisory.advisory_status(%{"content" => String.duplicate("a", 40)}, [], project_root)

    assert advisory.status == "skipped_no_provider"
    assert advisory.detail =~ "No CK-owned LLM provider is configured"
    assert advisory.detail =~ "codex-cli via codex_sdk"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
