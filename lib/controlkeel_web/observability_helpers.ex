defmodule ControlKeelWeb.ObservabilityHelpers do
  @moduledoc """
  Shared presentation helpers for observability pages.

  Imported explicitly (`import ControlKeelWeb.ObservabilityHelpers`) only in
  the modules that need it — deliberately NOT in the global `html_helpers`
  block, since other LiveViews still carry their own private copies of these
  names and a global import would collide with them. Migrate those call sites
  over one by one, then consider promoting this into `FormatHelpers`.
  """

  @doc """
  CSS class string for a red/yellow/green health pill. `size` is `:md`
  (default, `px-3 py-1.5 text-sm`) or `:sm` (`px-2 py-1 text-xs`, used by the
  recent-sessions table).
  """
  def health_pill_class(health, size \\ :md)

  def health_pill_class("red", size),
    do: "#{health_pill_base(size)} bg-destructive/10 text-destructive ring-destructive/20"

  def health_pill_class("yellow", size),
    do: "#{health_pill_base(size)} bg-warning/10 text-warning ring-warning/20"

  def health_pill_class(_, size),
    do: "#{health_pill_base(size)} bg-success/10 text-success ring-success/20"

  defp health_pill_base(:sm),
    do: "inline-flex items-center rounded-full px-2 py-1 text-xs font-semibold capitalize ring-1"

  defp health_pill_base(_),
    do: "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1"

  @doc """
  Formats integer cents as dollars. Non-integers return `0.0`.
  """
  def format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  def format_currency(_cents), do: 0.0

  @doc """
  Formats a `%{label => count}` frequency map as `"label: count, ..."` sorted
  by count descending, or `"none"` when empty.
  """
  def format_frequency(map) when map == %{}, do: "none"

  def format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  @doc """
  Short timestamp for observability tables (`"%Y-%m-%d %H:%M"`), `"—"` fallback.
  """
  def format_dt(nil), do: "—"
  def format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  def format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  def format_dt(_), do: "—"

  @doc """
  Formats a millisecond timing value, `"—"` fallback.
  """
  def format_ms(value) when is_number(value), do: "#{value} ms"
  def format_ms(_), do: "—"

  @doc """
  Formats a byte count, `"—"` fallback.
  """
  def format_bytes(nil), do: "—"
  def format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  def format_bytes(_), do: "—"

  @doc """
  Humanizes a snake_case blocker id (`"eval_stuck"` → `"Eval stuck"`).
  """
  def humanize_blocker_id(id) when is_binary(id) do
    id |> String.replace("_", " ") |> String.capitalize()
  end

  def humanize_blocker_id(id), do: inspect(id)
end
