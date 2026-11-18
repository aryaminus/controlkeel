defmodule ControlKeelWeb.FormatHelpers do
  @moduledoc """
  Shared presentation helpers imported into every view through the
  `html_helpers` block in `ControlKeelWeb`. Dependency-free: stdlib
  `Calendar`/`DateTime` only.

  Extracted from the private `format_datetime/1` copies that lived in
  `observability_problems_live`, `proof_browser_live`, and the session run
  page so every view formats timestamps the same way.
  """

  @doc """
  Formats a timestamp for display. Accepts a `DateTime`, `NaiveDateTime`,
  ISO8601 string, `nil`, or `""`. Unparseable strings pass through unchanged.

  `fallback` is returned for `nil`/`""` so callers can preserve page-specific
  empty-state copy (e.g. the proof browser shows "Not recorded"). Defaults to
  "unknown" to match the observability pages.
  """
  def format_datetime(value, fallback \\ "unknown")

  def format_datetime(nil, fallback), do: fallback
  def format_datetime("", fallback), do: fallback

  def format_datetime(%DateTime{} = dt, _fallback),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  def format_datetime(%NaiveDateTime{} = dt, _fallback),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

  def format_datetime(value, _fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
          _ -> value
        end
    end
  end

  def format_datetime(value, _fallback), do: to_string(value)

  @doc """
  Formats a date without a time component, e.g. `2026-11-25`.

  Used where only the day matters (invitation expiry). Accepts a `DateTime`,
  `NaiveDateTime`, `Date`, or `nil`; `fallback` is returned for nil/unknown
  input so callers can preserve page-specific copy.
  """
  def format_date(value, fallback \\ "unknown")

  def format_date(nil, fallback), do: fallback
  def format_date(%DateTime{} = dt, _fallback), do: Calendar.strftime(dt, "%Y-%m-%d")
  def format_date(%NaiveDateTime{} = ndt, _fallback), do: Calendar.strftime(ndt, "%Y-%m-%d")
  def format_date(%Date{} = date, _fallback), do: Calendar.strftime(date, "%Y-%m-%d")
  def format_date(_value, fallback), do: fallback

  @doc """
  CSS class string for a neutral pill/badge used in observability pages.
  Consolidated here to eliminate duplication across eight LiveViews.
  """
  def neutral_pill_class,
    do:
      "inline-flex items-center rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground"
end
