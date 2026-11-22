defmodule ControlKeel.Cloud.AgentInventory do
  @moduledoc """
  Filesystem-level discovery for "shadow AI" — agent host configurations sitting
  in a repository that ControlKeel doesn't yet govern.

  This is the local half of Branch 9 in the roadmap: walk a directory tree
  looking for the well-known config paths each agent host writes, then return a
  structured inventory. Network-level MCP probing and the browser-extension
  companion are out of scope here.

  Read-only. No filesystem writes, no DB persistence in this slice. Operators
  can `controlkeel agents discover <path> --json` and pipe the result into any
  tracking system they want; a future slice can persist into a dedicated
  inventory table when the org admin UI exists to manage it.

  ## Patterns

  Each pattern declares:
    - `host` — canonical agent host id (matches `Integration.catalog/0` ids
      where possible)
    - `relative_path` — directory or file relative to the repo root
    - `kind` — `:directory` | `:file`
    - `evidence` — short label rendered in the output (e.g. "cursor workspace")
  """

  @typedoc "One discovery hit."
  @type hit :: %{
          host: String.t(),
          path: String.t(),
          kind: :directory | :file,
          evidence: String.t()
        }

  @max_depth 5
  @skip_dirs ~w(node_modules .git deps _build .elixir_ls build dist target vendor .next .pnpm-store)

  @patterns [
    # Per-host repo-scoped directories
    %{
      host: "claude-code",
      relative_path: ".claude",
      kind: :directory,
      evidence: "claude-code repo dir"
    },
    %{host: "cursor", relative_path: ".cursor", kind: :directory, evidence: "cursor workspace"},
    %{host: "codex-cli", relative_path: ".codex", kind: :directory, evidence: "codex workspace"},
    %{
      host: "opencode",
      relative_path: ".opencode",
      kind: :directory,
      evidence: "opencode workspace"
    },
    %{
      host: "augment",
      relative_path: ".augment",
      kind: :directory,
      evidence: "augment workspace"
    },
    %{host: "warp", relative_path: ".warp", kind: :directory, evidence: "warp workspace"},
    %{
      host: "devin-terminal",
      relative_path: ".devin",
      kind: :directory,
      evidence: "devin terminal workspace"
    },
    %{host: "kiro", relative_path: ".kiro", kind: :directory, evidence: "kiro workspace"},
    %{
      host: "windsurf",
      relative_path: ".windsurf",
      kind: :directory,
      evidence: "windsurf workspace"
    },
    %{
      host: "continue",
      relative_path: ".continue",
      kind: :directory,
      evidence: "continue workspace"
    },
    %{host: "cline", relative_path: ".cline", kind: :directory, evidence: "cline workspace"},
    %{host: "goose", relative_path: ".goose", kind: :directory, evidence: "goose workspace"},
    %{host: "amp", relative_path: ".amp", kind: :directory, evidence: "amp workspace"},
    %{host: "kilo", relative_path: ".kilo", kind: :directory, evidence: "kilo workspace"},
    %{host: "pi", relative_path: ".pi", kind: :directory, evidence: "pi workspace"},
    %{host: "roo-code", relative_path: ".roo", kind: :directory, evidence: "roo workspace"},
    %{host: "letta-code", relative_path: ".letta", kind: :directory, evidence: "letta workspace"},

    # Cross-host conventions
    %{
      host: "agents-md",
      relative_path: "AGENTS.md",
      kind: :file,
      evidence: "AGENTS.md spec file"
    },
    %{
      host: "agents-skills",
      relative_path: ".agents",
      kind: :directory,
      evidence: "open AgentSkills bundle"
    },

    # Single-file conventions
    %{
      host: "claude-code",
      relative_path: "CLAUDE.md",
      kind: :file,
      evidence: "CLAUDE.md project instructions"
    },
    %{host: "kilo", relative_path: ".kilo/kilo.json", kind: :file, evidence: "kilo config"},
    %{
      host: "letta-code",
      relative_path: ".letta/settings.json",
      kind: :file,
      evidence: "letta settings"
    },
    %{
      host: "windsurf",
      relative_path: ".windsurf/hooks.json",
      kind: :file,
      evidence: "windsurf hook config"
    }
  ]

  @doc "Patterns the discoverer recognises (mostly used by tests)."
  @spec patterns() :: [map()]
  def patterns, do: @patterns

  @doc """
  Walk a directory tree (up to `:max_depth`, default 5) collecting agent-host
  evidence. Returns `{:ok, hits}` (possibly empty) or `{:error, reason}` when
  the path doesn't exist.

  Options:
    - `:max_depth` — directory descent cap (default 5)
    - `:skip_dirs` — directory names skipped at any depth (default common build
      dirs)
  """
  @spec scan(String.t(), keyword()) :: {:ok, [hit()]} | {:error, atom()}
  def scan(root, opts \\ []) when is_binary(root) do
    expanded = Path.expand(root)

    cond do
      not File.exists?(expanded) ->
        {:error, :not_found}

      not File.dir?(expanded) ->
        {:error, :not_a_directory}

      true ->
        max_depth = Keyword.get(opts, :max_depth, @max_depth)
        skip = Keyword.get(opts, :skip_dirs, @skip_dirs) |> MapSet.new()

        hits =
          collect(expanded, expanded, 0, max_depth, skip)
          |> Enum.uniq_by(&{&1.host, &1.path})
          |> Enum.sort_by(&{&1.host, &1.path})

        {:ok, hits}
    end
  end

  @doc """
  Roll a list of hits up into a per-host summary suitable for dashboards or
  CLI output.
  """
  @spec summarize([hit()]) :: %{
          total: non_neg_integer(),
          by_host: [%{host: String.t(), count: non_neg_integer(), evidence: [String.t()]}]
        }
  def summarize(hits) when is_list(hits) do
    by_host =
      hits
      |> Enum.group_by(& &1.host)
      |> Enum.map(fn {host, host_hits} ->
        %{
          host: host,
          count: length(host_hits),
          evidence: host_hits |> Enum.map(& &1.evidence) |> Enum.uniq() |> Enum.sort()
        }
      end)
      |> Enum.sort_by(&{-&1.count, &1.host})

    %{total: length(hits), by_host: by_host}
  end

  defp collect(current, root, depth, max_depth, skip) do
    if depth > max_depth do
      []
    else
      hits_here = matches_at(current, root)

      sub_hits =
        case File.ls(current) do
          {:ok, entries} ->
            entries
            |> Enum.filter(fn name ->
              full = Path.join(current, name)
              File.dir?(full) and not MapSet.member?(skip, name)
            end)
            |> Enum.flat_map(fn name ->
              collect(Path.join(current, name), root, depth + 1, max_depth, skip)
            end)

          _ ->
            []
        end

      hits_here ++ sub_hits
    end
  end

  defp matches_at(directory, root) do
    @patterns
    |> Enum.flat_map(fn pattern ->
      candidate = Path.join(directory, pattern.relative_path)
      ok? = pattern.kind == :directory and File.dir?(candidate)
      ok? = ok? or (pattern.kind == :file and File.regular?(candidate))

      if ok? do
        [
          %{
            host: pattern.host,
            path: relative_to(candidate, root),
            kind: pattern.kind,
            evidence: pattern.evidence
          }
        ]
      else
        []
      end
    end)
  end

  defp relative_to(path, root) do
    case Path.relative_to(path, root) do
      ^path -> path
      rel -> rel
    end
  end
end
