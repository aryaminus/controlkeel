defmodule ControlKeel.CLI.JsonModeTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO

  alias ControlKeel.CLI
  alias ControlKeel.CLI.Output

  defp decode_json(output) do
    Jason.decode!(String.trim(output))
  end

  describe "JSON error envelopes" do
    test "unknown command with --json returns JSON error envelope" do
      assert {:error, _message} = CLI.parse(["nonexistent-command", "--json"])
    end

    test "run_command error in JSON mode outputs structured JSON to stdout" do
      output =
        capture_io(fn ->
          assert 1 ==
                   CLI.execute(
                     %{command: :proof, options: %{json: true}, args: ["999999999"]},
                     project_root: System.tmp_dir!()
                   )
        end)

      assert String.starts_with?(String.trim(output), "{")
      payload = decode_json(output)
      assert payload["status"] == "error"
      assert is_binary(payload["error"])
      assert payload["code"] == "command_error"
      assert payload["command"] == "proof <id>"
      assert is_binary(payload["version"])
    end

    test "run_command error in text mode outputs plain text to stderr" do
      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          CLI.execute(
            %{command: :proof, options: %{}, args: ["999999999"]},
            project_root: System.tmp_dir!()
          )
        end)

      assert stderr =~ "not found"
    end

    test "execute routes errors through json_error_printer in JSON mode" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      capture_io(fn ->
        CLI.execute(
          %{command: :help, options: %{json: true}, args: []},
          json_error_printer: fn line ->
            Agent.update(agent, fn acc -> [{:json_error, line} | acc] end)
          end,
          printer: fn line ->
            Agent.update(agent, fn acc -> [{:stdout, line} | acc] end)
          end
        )
      end)

      calls = Agent.get(agent, & &1) |> Enum.reverse()
      assert Enum.any?(calls, fn {type, _} -> type == :stdout end)
      refute Enum.any?(calls, fn {type, _} -> type == :json_error end)

      Agent.stop(agent)
    end
  end

  describe "JSON mode detection" do
    test "json_mode? detects --json flag" do
      parsed = %{command: :doctor, options: %{json: true}, args: []}
      assert CLI.json_mode?(parsed)
    end

    test "json_mode? detects --format json" do
      parsed = %{command: :doctor, options: %{format: "json"}, args: []}
      assert CLI.json_mode?(parsed)
    end

    test "json_mode? detects --format JSON (uppercase)" do
      parsed = %{command: :doctor, options: %{format: "JSON"}, args: []}
      assert CLI.json_mode?(parsed)
    end

    test "json_mode? returns false for plain text mode" do
      parsed = %{command: :doctor, options: %{}, args: []}
      refute CLI.json_mode?(parsed)
    end
  end

  describe "clean JSON output (no log noise)" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "controlkeel-json-#{System.unique_integer([:positive])}")

      File.rm_rf!(tmp_dir)
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "doctor --json produces only valid JSON on stdout", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          assert 0 ==
                   CLI.execute(%{command: :doctor, options: %{json: true}, args: []},
                     project_root: tmp_dir
                   )
        end)

      assert String.starts_with?(String.trim(output), "{")
      payload = decode_json(output)
      assert payload["status"] == "ok"
      assert is_binary(payload["version"])
      refute output =~ "\n\n"
      refute output =~ "[info]"
      refute output =~ "[warning]"
      refute output =~ "[debug]"
    end

    test "capabilities --json produces only valid JSON on stdout" do
      output =
        capture_io(fn ->
          assert 0 == CLI.execute(%{command: :capabilities, options: %{json: true}, args: []})
        end)

      assert String.starts_with?(String.trim(output), "{")
      payload = decode_json(output)
      assert payload["status"] == "ok"
      assert is_binary(payload["version"])
      refute output =~ "[info]"
      refute output =~ "[warning]"
    end
  end

  describe "Output.error_json/4" do
    test "produces well-formed error envelope with nil entry" do
      json = Output.error_json("something went wrong", :test_error, nil)
      payload = Jason.decode!(json)

      assert payload["status"] == "error"
      assert payload["error"] == "something went wrong"
      assert payload["code"] == "test_error"
      assert payload["command"] == nil
      assert payload["hint"] == "Run: controlkeel help"
      assert is_binary(payload["version"])
      assert payload["details"] == %{}
    end

    test "produces well-formed error envelope with catalog entry" do
      entry = ControlKeel.CLI.Catalog.for_command(:doctor)
      json = Output.error_json("doctor failed", :doctor_error, entry)
      payload = Jason.decode!(json)

      assert payload["status"] == "error"
      assert payload["error"] == "doctor failed"
      assert payload["code"] == "doctor_error"
      assert payload["command"] == "doctor"
      assert payload["hint"] == "Run: controlkeel doctor --help"
      assert is_binary(payload["version"])
    end
  end

  describe "Output.json_requested?/1" do
    test "detects --json in argv" do
      assert Output.json_requested?(["doctor", "--json"])
    end

    test "detects --format json in argv" do
      assert Output.json_requested?(["doctor", "--format", "json"])
    end

    test "returns false when no json flag present" do
      refute Output.json_requested?(["doctor"])
    end
  end
end
