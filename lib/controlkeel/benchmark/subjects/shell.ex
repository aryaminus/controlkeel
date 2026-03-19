defmodule ControlKeel.Benchmark.Subjects.Shell do
  @moduledoc false

  alias ControlKeel.Benchmark.Runner
  alias ControlKeel.Benchmark.Scenario

  def run(%Scenario{} = scenario, subject, opts \\ []) do
    project_root = Path.expand(opts[:project_root] || File.cwd!())

    case subject do
      %{"configured" => false} ->
        Runner.placeholder_outcome("skipped_unconfigured", subject)

      %{"command" => command} when is_binary(command) and command != "" ->
        execute_shell_subject(scenario, subject, project_root)

      _other ->
        Runner.placeholder_outcome("skipped_unconfigured", subject)
    end
  end

  defp execute_shell_subject(%Scenario{} = scenario, subject, project_root) do
    started_at = System.monotonic_time(:millisecond)
    tmp_root = temp_dir()
    prompt_file = Path.join(tmp_root, "prompt.txt")
    scenario_file = Path.join(tmp_root, "scenario.json")
    output_dir = Path.join(tmp_root, "output")
    working_dir = Path.join(tmp_root, subject["working_dir"] || "workspace")

    File.mkdir_p!(output_dir)
    File.mkdir_p!(working_dir)
    File.write!(prompt_file, prompt_for(scenario))
    File.write!(scenario_file, Jason.encode!(scenario_payload(scenario), pretty: true))

    env = [
      {"CONTROLKEEL_BENCHMARK_PROMPT_FILE", prompt_file},
      {"CONTROLKEEL_BENCHMARK_SCENARIO_FILE", scenario_file},
      {"CONTROLKEEL_BENCHMARK_OUTPUT_DIR", output_dir},
      {"CONTROLKEEL_PROJECT_ROOT", project_root}
    ]

    outcome =
      try do
        case run_command(subject, working_dir, env) do
          {:ok, output, exit_status} ->
            scan_payload =
              Runner.scan_generated_output(
                output,
                output_dir,
                scenario,
                Map.get(subject, "output_mode", "stdout")
              )

            status = if exit_status == 0, do: "completed", else: "failed"

            Runner.merge_payload(
              scan_payload,
              %{
                "status" => status,
                "latency_ms" => System.monotonic_time(:millisecond) - started_at,
                "metadata" => %{
                  "runner" => "shell",
                  "command" => subject["command"],
                  "args" => subject["args"] || [],
                  "exit_status" => exit_status,
                  "working_dir" => working_dir
                },
                "payload" => %{
                  "stdout" => output,
                  "output_files" => Runner.output_files(output_dir),
                  "exit_status" => exit_status
                }
              }
            )

          :timeout ->
            Runner.error_outcome(
              "timed_out",
              "Shell subject timed out",
              System.monotonic_time(:millisecond) - started_at
            )
        end
      rescue
        error ->
          Runner.error_outcome(
            "failed",
            Exception.message(error),
            System.monotonic_time(:millisecond) - started_at
          )
      after
        File.rm_rf(tmp_root)
      end

    outcome
  end

  defp temp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-benchmark-shell-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp run_command(subject, working_dir, env) do
    timeout_ms = subject["timeout_ms"] || 30_000

    task =
      Task.async(fn ->
        System.cmd(subject["command"], subject["args"] || [],
          cd: working_dir,
          env: env,
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_status}} -> {:ok, output, exit_status}
      _other -> :timeout
    end
  end

  defp prompt_for(%Scenario{} = scenario) do
    scenario.metadata["prompt"] ||
      """
      Produce an artifact for this benchmark scenario.
      Scenario: #{scenario.name}
      Category: #{scenario.category}
      Write your output to the benchmark output directory or stdout.
      """
      |> String.trim()
  end

  defp scenario_payload(%Scenario{} = scenario) do
    %{
      "slug" => scenario.slug,
      "name" => scenario.name,
      "category" => scenario.category,
      "incident_label" => scenario.incident_label,
      "path" => scenario.path,
      "kind" => scenario.kind,
      "content" => scenario.content,
      "expected_rules" => scenario.expected_rules,
      "expected_decision" => scenario.expected_decision,
      "metadata" => scenario.metadata
    }
  end
end
