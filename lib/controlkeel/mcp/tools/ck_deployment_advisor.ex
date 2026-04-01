defmodule ControlKeel.MCP.Tools.CkDeploymentAdvisor do
  @moduledoc false

  alias ControlKeel.Deployment.Advisor

  @allowed_modes ~w(analyze generate_files dns_guide)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      case normalized["mode"] do
        "analyze" ->
          Advisor.analyze(normalized["project_root"])

        "generate_files" ->
          case Advisor.analyze(normalized["project_root"]) do
            {:ok, analysis} ->
              Advisor.generate_files(normalized["project_root"], analysis.generators,
                dry_run: normalized["dry_run"]
              )
          end

        "dns_guide" ->
          case Advisor.analyze(normalized["project_root"]) do
            {:ok, analysis} ->
              {:ok, Advisor.dns_ssl_guide(analysis.stack)}
          end
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, mode} <- mode(arguments),
         {:ok, project_root} <- required_string(arguments, "project_root") do
      {:ok,
       %{
         "mode" => mode,
         "project_root" => project_root,
         "dry_run" => Map.get(arguments, "dry_run", false)
       }}
    end
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "analyze") do
      value when value in @allowed_modes ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`mode` must be `analyze`, `generate_files`, or `dns_guide`"}}
    end
  end

  defp required_string(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a string"}}
    end
  end
end
