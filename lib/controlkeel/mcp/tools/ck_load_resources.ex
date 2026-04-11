defmodule ControlKeel.MCP.Tools.CkLoadResources do
  @moduledoc """
  MCP tool: ck_load_resources

  Fallback for clients that do not support MCP resources. Currently supports
  `skills://<name>` URIs and returns the same rendered skill content CK exposes
  through MCP resources/read.
  """

  alias ControlKeel.MCP.Tools.CkSkillLoad

  def call(%{"uris" => uris} = arguments) when is_list(uris) do
    project_root = Map.get(arguments, "project_root")
    target = Map.get(arguments, "target")
    session_id = Map.get(arguments, "session_id")

    with {:ok, entries} <- load_entries(uris, project_root, target, session_id) do
      {:ok, %{"resources" => entries, "total" => length(entries)}}
    end
  end

  def call(_arguments) do
    {:error, {:invalid_arguments, "uris is required"}}
  end

  def load_resource_uri("skills://" <> name, project_root, target, session_id) do
    arguments =
      %{"name" => name}
      |> maybe_put("project_root", project_root)
      |> maybe_put("target", target)
      |> maybe_put("session_id", session_id)

    case CkSkillLoad.call(arguments) do
      {:ok, result} ->
        {:ok,
         %{
           "uri" => "skills://#{name}",
           "name" => result["name"],
           "description" => result["description"],
           "mimeType" => "text/markdown",
           "text" => result["content"],
           "resources" => result["resources"]
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def load_resource_uri(uri, _project_root, _target, _session_id) do
    {:error, {:invalid_arguments, "Unsupported resource URI: #{uri}"}}
  end

  defp load_entries(uris, project_root, target, session_id) do
    Enum.reduce_while(uris, {:ok, []}, fn uri, {:ok, acc} ->
      case load_resource_uri(uri, project_root, target, session_id) do
        {:ok, entry} -> {:cont, {:ok, acc ++ [entry]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
