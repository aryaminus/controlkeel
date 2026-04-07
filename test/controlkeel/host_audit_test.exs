defmodule ControlKeel.HostAuditTest do
  use ExUnit.Case, async: true

  alias ControlKeel.HostAudit

  test "reports ok, warn, and error counts from the injected fetcher" do
    fetcher = fn
      {:npm_package, "@aryaminus/controlkeel"} ->
        %{status: :ok, detail: "latest 0.1.31"}

      {:npm_package, _package} ->
        %{status: :warn, detail: "rate limited"}

      {:url, url} ->
        if String.contains?(url, "anthropic"),
          do: %{status: :error, detail: "HTTP 404"},
          else: %{status: :ok, detail: "HTTP 200"}
    end

    report = HostAudit.run(fetcher: fetcher)

    assert report.summary.ok > 0
    assert report.summary.warn > 0
    assert report.summary.error > 0

    assert Enum.any?(report.checks, fn check ->
             check.type == :npm_package and check.id == "@aryaminus/controlkeel"
           end)
  end
end
