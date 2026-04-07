defmodule ControlKeel.HostAudit do
  @moduledoc false

  alias ControlKeel.AgentIntegration

  @npm_packages [
    "@aryaminus/controlkeel",
    "@aryaminus/controlkeel-opencode",
    "@aryaminus/controlkeel-pi-extension"
  ]

  @release_urls [
    "https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh",
    "https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh"
  ]

  def run(opts \\ []) do
    fetcher = Keyword.get(opts, :fetcher, &default_fetch/1)
    include_unverified? = Keyword.get(opts, :include_unverified, false)

    integration_urls =
      AgentIntegration.catalog()
      |> Enum.reject(&(not include_unverified? and &1.support_class == "unverified"))
      |> Enum.map(fn integration -> {integration.id, integration.upstream_docs_url} end)
      |> Enum.reject(fn {_id, url} -> is_nil(url) or String.trim(url) == "" end)

    repo_slug_checks =
      AgentIntegration.catalog()
      |> Enum.reject(&(not include_unverified? and &1.support_class == "unverified"))
      |> Enum.filter(&repo_slug_checkable?/1)
      |> Enum.uniq_by(& &1.upstream_slug)
      |> Enum.map(fn integration ->
        %{
          type: :repo_slug,
          id: integration.id,
          url: "https://github.com/#{integration.upstream_slug}",
          result: fetcher.({:repo_slug, integration.upstream_slug})
        }
      end)

    url_checks =
      integration_urls
      |> Enum.map(fn {id, url} ->
        %{
          type: :integration_url,
          id: id,
          url: url,
          result: fetcher.({:url, url})
        }
      end)

    npm_checks =
      Enum.map(@npm_packages, fn package ->
        %{
          type: :npm_package,
          id: package,
          url: "https://registry.npmjs.org/#{URI.encode(package)}",
          result: fetcher.({:npm_package, package})
        }
      end)

    release_checks =
      Enum.map(@release_urls, fn url ->
        %{
          type: :release_url,
          id: url,
          url: url,
          result: fetcher.({:url, url})
        }
      end)

    all_checks = repo_slug_checks ++ url_checks ++ npm_checks ++ release_checks

    %{
      checks: all_checks,
      summary: summarize(all_checks)
    }
  end

  def render(report) do
    lines = [
      "Host audit summary: #{report.summary.ok} ok, #{report.summary.warn} warn, #{report.summary.error} error"
    ]

    lines ++
      Enum.map(report.checks, fn check ->
        "#{status_label(check.result.status)} [#{check.type}] #{check.id} -> #{result_label(check.result)}"
      end)
  end

  defp summarize(checks) do
    Enum.reduce(checks, %{ok: 0, warn: 0, error: 0}, fn check, acc ->
      Map.update!(acc, check.result.status, &(&1 + 1))
    end)
  end

  defp default_fetch({:url, url}) do
    req =
      Req.new(
        url: url,
        method: :head,
        headers: [{"user-agent", "controlkeel-host-audit"}],
        receive_timeout: 15_000
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: status}} when status in 200..399 ->
        %{status: :ok, detail: "HTTP #{status}"}

      {:ok, %Req.Response{status: status}} ->
        %{status: classify_http(status), detail: "HTTP #{status}"}

      {:error, exception} ->
        %{status: :error, detail: Exception.message(exception)}
    end
  end

  defp default_fetch({:repo_slug, slug}) do
    default_fetch({:url, "https://github.com/#{slug}"})
  end

  defp default_fetch({:npm_package, package}) do
    url = "https://registry.npmjs.org/#{URI.encode(package)}"

    req =
      Req.new(
        url: url,
        method: :get,
        headers: [{"user-agent", "controlkeel-host-audit"}],
        receive_timeout: 15_000
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        latest = get_in(body, ["dist-tags", "latest"])

        if is_binary(latest) do
          %{status: :ok, detail: "latest #{latest}"}
        else
          %{status: :warn, detail: "missing dist-tags.latest"}
        end

      {:ok, %Req.Response{status: status}} ->
        %{status: classify_http(status), detail: "HTTP #{status}"}

      {:error, exception} ->
        %{status: :error, detail: Exception.message(exception)}
    end
  end

  defp classify_http(status) when status in [401, 403, 405, 429], do: :warn
  defp classify_http(status) when status in 400..499, do: :error
  defp classify_http(status) when status in 500..599, do: :error
  defp classify_http(_status), do: :warn

  defp repo_slug_checkable?(integration) do
    is_binary(integration.upstream_slug) and
      Regex.match?(~r/^[^\/]+\/[^\/]+$/, integration.upstream_slug) and
      is_binary(integration.upstream_docs_url) and
      String.starts_with?(integration.upstream_docs_url, "https://github.com/")
  end

  defp status_label(:ok), do: "OK"
  defp status_label(:warn), do: "WARN"
  defp status_label(:error), do: "ERROR"

  defp result_label(%{detail: detail}), do: detail
end
