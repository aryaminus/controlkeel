defmodule ControlKeel.Cloud.AgentInventoryTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.AgentInventory

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "ck-agent-inv-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "scan/2 errors" do
    test "returns :not_found for a missing path" do
      assert {:error, :not_found} =
               AgentInventory.scan(
                 "/definitely/does/not/exist/-#{System.unique_integer([:positive])}"
               )
    end

    test "returns :not_a_directory when path is a file", %{tmp: tmp} do
      file = Path.join(tmp, "regular.txt")
      File.write!(file, "hi")
      assert {:error, :not_a_directory} = AgentInventory.scan(file)
    end
  end

  describe "scan/2 happy paths" do
    test "empty directory yields no hits", %{tmp: tmp} do
      assert {:ok, []} = AgentInventory.scan(tmp)
    end

    test "detects top-level agent directories", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, ".cursor"))
      File.mkdir_p!(Path.join(tmp, ".codex"))
      File.mkdir_p!(Path.join(tmp, ".claude"))

      {:ok, hits} = AgentInventory.scan(tmp)

      hosts = Enum.map(hits, & &1.host) |> Enum.sort()
      assert "cursor" in hosts
      assert "codex-cli" in hosts
      assert "claude-code" in hosts
      assert Enum.all?(hits, &(&1.kind == :directory))
    end

    test "detects single-file conventions", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), "# agents")
      File.write!(Path.join(tmp, "CLAUDE.md"), "# claude")

      {:ok, hits} = AgentInventory.scan(tmp)

      hosts = hits |> Enum.map(& &1.host) |> Enum.sort()
      assert "agents-md" in hosts
      assert "claude-code" in hosts
      refute "aider" in hosts
    end

    test "recurses into nested project subdirectories", %{tmp: tmp} do
      nested = Path.join([tmp, "team", "project-x"])
      File.mkdir_p!(Path.join(nested, ".opencode"))
      File.mkdir_p!(Path.join(nested, ".cursor"))

      {:ok, hits} = AgentInventory.scan(tmp)
      assert Enum.find(hits, &(&1.host == "opencode" and String.contains?(&1.path, "project-x")))
      assert Enum.find(hits, &(&1.host == "cursor" and String.contains?(&1.path, "project-x")))
    end

    test "skips noisy directories like node_modules and .git", %{tmp: tmp} do
      File.mkdir_p!(Path.join([tmp, "node_modules", "evil-pkg", ".cursor"]))
      File.mkdir_p!(Path.join([tmp, ".git", "hooks"]))
      File.mkdir_p!(Path.join(tmp, ".cursor"))

      {:ok, hits} = AgentInventory.scan(tmp)

      paths = Enum.map(hits, & &1.path)
      refute Enum.any?(paths, &String.contains?(&1, "node_modules"))
      assert Enum.any?(paths, &(&1 == ".cursor"))
    end

    test "max_depth bounds the descent", %{tmp: tmp} do
      deep = Path.join([tmp, "a", "b", "c", "d", "e", "f"])
      File.mkdir_p!(Path.join(deep, ".cursor"))

      {:ok, shallow} = AgentInventory.scan(tmp, max_depth: 2)
      assert shallow == []

      {:ok, deep_hits} = AgentInventory.scan(tmp, max_depth: 10)
      assert Enum.any?(deep_hits, &(&1.host == "cursor"))
    end

    test "results are deduped and sorted", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, ".cursor"))
      File.mkdir_p!(Path.join([tmp, "subproject", ".cursor"]))

      {:ok, hits} = AgentInventory.scan(tmp)
      cursor_hits = Enum.filter(hits, &(&1.host == "cursor"))
      assert length(cursor_hits) == 2
      assert Enum.map(cursor_hits, & &1.path) == Enum.sort(Enum.map(cursor_hits, & &1.path))
    end
  end

  describe "summarize/1" do
    test "groups hits by host, sorted by descending count then host name" do
      hits = [
        %{host: "cursor", path: "a/.cursor", kind: :directory, evidence: "cursor workspace"},
        %{host: "cursor", path: "b/.cursor", kind: :directory, evidence: "cursor workspace"},
        %{host: "codex-cli", path: ".codex", kind: :directory, evidence: "codex workspace"}
      ]

      summary = AgentInventory.summarize(hits)
      assert summary.total == 3
      assert [%{host: "cursor", count: 2} | _] = summary.by_host
      assert Enum.find(summary.by_host, &(&1.host == "codex-cli")).count == 1
    end

    test "returns empty summary for empty hits" do
      assert %{total: 0, by_host: []} = AgentInventory.summarize([])
    end
  end

  describe "patterns/0" do
    test "every entry has the expected keys" do
      for pattern <- AgentInventory.patterns() do
        assert Map.has_key?(pattern, :host)
        assert Map.has_key?(pattern, :relative_path)
        assert pattern.kind in [:directory, :file]
        assert is_binary(pattern.evidence)
      end
    end

    test "host ids are non-empty strings" do
      hosts = AgentInventory.patterns() |> Enum.map(& &1.host) |> Enum.uniq()
      assert Enum.all?(hosts, &(is_binary(&1) and &1 != ""))
    end
  end
end
