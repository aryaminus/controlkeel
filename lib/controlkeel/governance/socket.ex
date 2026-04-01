defmodule ControlKeel.Governance.Socket do
  @moduledoc false

  @issue_collections [
    ["issues"],
    ["alerts"],
    ["results"],
    ["findings"],
    ["data", "issues"],
    ["data", "alerts"],
    ["report", "issues"],
    ["report", "alerts"]
  ]

  def dependency_review(%{} = report) do
    issues =
      report
      |> extract_issue_maps()
      |> Enum.map(&normalize_issue/1)

    if issues == [] do
      {:error, "Socket report did not contain dependency issues."}
    else
      {:ok, %{"issues" => issues}}
    end
  end

  def dependency_review(_report), do: {:error, "Socket report must be a JSON object."}

  defp extract_issue_maps(report) do
    @issue_collections
    |> Enum.reduce_while([], fn path, _acc ->
      case get_in(report, path) do
        list when is_list(list) ->
          {:halt, Enum.filter(list, &is_map/1)}

        _ ->
          {:cont, []}
      end
    end)
  end

  defp normalize_issue(issue) do
    advisory = issue["advisory"] || %{}
    package = package_name(issue)

    %{
      "package" => package,
      "severity" => severity(issue),
      "summary" => summary(issue, advisory),
      "manifest_path" => manifest_path(issue),
      "rule_id" => "dependencies.socket.alert",
      "advisory_id" => advisory_id(issue, advisory),
      "source" => "socket"
    }
    |> Map.merge(maybe_extra_metadata(issue))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp package_name(issue) do
    issue["package"] ||
      issue["dependency"] ||
      get_in(issue, ["package", "name"]) ||
      get_in(issue, ["dependency", "name"]) ||
      get_in(issue, ["artifact", "name"]) ||
      "Dependency"
  end

  defp severity(issue) do
    issue["severity"] ||
      issue["risk"] ||
      issue["threat_level"] ||
      get_in(issue, ["advisory", "severity"]) ||
      "medium"
  end

  defp summary(issue, advisory) do
    issue["summary"] ||
      issue["message"] ||
      issue["title"] ||
      advisory["summary"] ||
      advisory["title"] ||
      "Socket reported a dependency issue."
  end

  defp manifest_path(issue) do
    issue["manifest_path"] || issue["file"] || issue["path"] || "dependency-review"
  end

  defp advisory_id(issue, advisory) do
    issue["advisory_id"] || issue["cve"] || issue["id"] || advisory["id"]
  end

  defp maybe_extra_metadata(issue) do
    metadata = %{}

    metadata =
      if is_binary(issue["ecosystem"]) do
        Map.put(metadata, "ecosystem", issue["ecosystem"])
      else
        metadata
      end

    if is_binary(issue["action"]) do
      Map.put(metadata, "action", issue["action"])
    else
      metadata
    end
  end
end
