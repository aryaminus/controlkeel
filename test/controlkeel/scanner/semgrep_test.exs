defmodule ControlKeel.Scanner.SemgrepTest do
  use ControlKeel.DataCase

  alias ControlKeel.Proxy
  alias ControlKeel.Scanner.Semgrep

  setup do
    previous = Application.get_env(:controlkeel, Proxy, [])

    on_exit(fn ->
      Application.put_env(:controlkeel, Proxy, previous)
    end)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-semgrep-test-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "scan returns normalized findings when semgrep succeeds", %{tmp_dir: tmp_dir} do
    bin =
      write_script(tmp_dir, "semgrep-ok", """
      #!/bin/sh
      cat <<'JSON'
      {"results":[{"check_id":"controlkeel.sql-injection","path":"snippet_1.js","start":{"line":1},"end":{"line":1},"extra":{"message":"bad query","severity":"ERROR","lines":"query = format(\\"SELECT * FROM users WHERE name = %s\\", user_input)","metadata":{"controlkeel_category":"security","controlkeel_rule_id":"security.semgrep.sql_injection","controlkeel_decision":"block","controlkeel_severity":"high"}}}]}
      JSON
      """)

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(Application.get_env(:controlkeel, Proxy, []), semgrep_bin: bin)
    )

    assert {:ok, %{status: :ok, findings: [finding]}} =
             Semgrep.scan(%{
               "content" =>
                 "```js\nquery = format(\"SELECT * FROM users WHERE name = %s\", user_input)\n```",
               "kind" => "text"
             })

    assert finding.rule_id == "security.semgrep.sql_injection"
    assert finding.decision == "block"
    assert finding.metadata["scanner"] == "semgrep"
  end

  test "scan returns unavailable cleanly when semgrep is missing" do
    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(Application.get_env(:controlkeel, Proxy, []),
        semgrep_bin: "/tmp/missing-semgrep"
      )
    )

    assert :unavailable =
             Semgrep.scan(%{"content" => "```js\nconst x = 1\n```", "kind" => "text"})
  end

  test "scan degrades gracefully on malformed output", %{tmp_dir: tmp_dir} do
    bin = write_script(tmp_dir, "semgrep-malformed", "#!/bin/sh\necho 'not-json'\n")

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(Application.get_env(:controlkeel, Proxy, []), semgrep_bin: bin)
    )

    assert {:ok, %{status: :malformed_output, findings: []}} =
             Semgrep.scan(%{"content" => "```js\nconst html = userInput\n```", "kind" => "text"})
  end

  test "scan times out and falls back cleanly", %{tmp_dir: tmp_dir} do
    bin =
      write_script(tmp_dir, "semgrep-timeout", "#!/bin/sh\nsleep 1\necho '{\"results\":[]}'\n")

    Application.put_env(
      :controlkeel,
      Proxy,
      Keyword.merge(Application.get_env(:controlkeel, Proxy, []),
        semgrep_bin: bin,
        timeout_ms: 50
      )
    )

    assert {:ok, %{status: :timeout, findings: []}} =
             Semgrep.scan(%{"content" => "```js\nconst html = userInput\n```", "kind" => "text"},
               timeout_ms: 50
             )
  end

  defp write_script(tmp_dir, name, contents) do
    path = Path.join(tmp_dir, name)
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end
end
