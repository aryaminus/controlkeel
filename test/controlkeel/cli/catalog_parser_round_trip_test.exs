defmodule ControlKeel.CLI.CatalogParserRoundTripTest do
  use ExUnit.Case, async: true

  alias ControlKeel.CLI
  alias ControlKeel.CLI.Catalog

  test "every catalog path parses to its command" do
    failures =
      Catalog.all()
      |> Enum.flat_map(fn entry ->
        argv = argv_for_path(entry.path)

        case CLI.parse(argv) do
          {:ok, %{command: command}} when command == entry.command ->
            []

          {:ok, %{command: other}} ->
            [{entry.command, entry.path, "parsed as #{inspect(other)}"}]

          {:error, message} ->
            [{entry.command, entry.path, "parse error: #{message}"}]
        end
      end)

    assert failures == [],
           "catalog paths that do not parse to their command: #{inspect(failures, pretty: true)}"
  end

  # Catalog paths carry `<placeholder>` args; the parser needs a concrete
  # token in each position. Integer-id positions need digits (benchmark
  # drafts, session ids); agent/host names must be known ids; `[id]`
  # optional positions are dropped to hit the zero-arg clause.
  @attachable_agent "claude-code"
  @plugin_host "claude"
  @provider_source "openai"

  defp argv_for_path(path) do
    tokens =
      path
      |> String.split(" ")
      |> Enum.reject(&(&1 == ""))

    tokens =
      case tokens do
        ["attach", "<agent>" | rest] -> ["attach", @attachable_agent | rest]
        ["detach", "<agent>" | rest] -> ["detach", @attachable_agent | rest]
        ["plugin", action, "<host>"] -> ["plugin", action, @plugin_host]
        ["provider", "default"] -> ["provider", "default", @provider_source]
        _ -> tokens
      end

    Enum.flat_map(tokens, fn
      "<" <> _ -> ["1"]
      "[id]" -> []
      token -> [token]
    end)
  end
end
