defmodule ControlKeelWeb.SitemapController do
  use ControlKeelWeb, :controller

  @moduledoc """
  Serves /sitemap.xml with all indexable public URLs.
  """

  @base_url "https://controlkeel.com"

  def index(conn, _params) do
    urls = public_urls()

    xml =
      Enum.map_join(urls, "\n", fn {path, changefreq, priority} ->
        """
            <url>
              <loc>#{@base_url}#{path}</loc>
              <changefreq>#{changefreq}</changefreq>
              <priority>#{priority}</priority>
            </url>
        """
      end)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{xml}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_resp(200, body)
  end

  defp public_urls do
    [
      {"/", "weekly", "1.0"},
      {"/docs", "weekly", "0.9"},
      {"/docs/getting-started", "weekly", "0.9"},
      {"/docs/agents", "weekly", "0.8"},
      {"/docs/governance", "weekly", "0.8"},
      {"/docs/observability", "weekly", "0.8"},
      {"/about", "monthly", "0.7"},
      {"/contact", "monthly", "0.6"},
      {"/developers", "weekly", "0.8"},
      {"/openapi.json", "monthly", "0.7"},
      {"/llms.txt", "monthly", "0.6"},
      {"/robots.txt", "monthly", "0.3"},
      {"/sitemap.xml", "monthly", "0.3"}
    ]
  end
end
