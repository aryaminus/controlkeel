defmodule ControlKeelWeb.ProofComponents do
  @moduledoc """
  Shared presentation helpers for the session-scoped proof views
  (`SessionProofsLive` and `ProofLive`): bundle accessors, status pill
  classes, related-memory lookup, and the session breadcrumb prefix.

  One source of truth per pattern — both views must render the same proof
  the same way, so these live here instead of being copied per LiveView.
  """

  alias ControlKeel.Memory

  @doc """
  Reads a nested value out of a proof bundle map, returning `default`
  when the proof or the path is missing.
  """
  def bundle_get(proof, keys, default \\ nil) do
    if proof, do: get_in(proof.bundle || %{}, keys) || default, else: default
  end

  @doc "Related memory for a proof: task-linked records, falling back to search."
  def related_memory_hits(proof) do
    related = Memory.list_related_to_task(proof.task_id, 5)

    if related != [] do
      related
    else
      Memory.search(proof.task.title,
        session_id: proof.session_id,
        task_id: proof.task_id,
        top_k: 5
      ).entries
    end
  end

  @doc """
  The org → workspace → session breadcrumb prefix. Callers append their
  page-specific tail (e.g. `[%{label: "Proofs", to: nil}]`).
  """
  def session_breadcrumb_base(org, workspace, session) do
    [
      %{label: org.name, to: "/#{org.slug}"},
      %{label: workspace.name, to: "/#{org.slug}/workspaces/#{workspace.slug}"},
      %{
        label: session.title,
        to: "/#{org.slug}/workspaces/#{workspace.slug}/sessions/#{session.id}"
      }
    ]
  end

  def verification_score_color(score) when is_integer(score) do
    cond do
      score >= 80 -> "text-primary"
      score >= 50 -> "text-warning"
      true -> "text-destructive"
    end
  end

  def verification_score_color(_), do: "text-muted-foreground"

  def verification_status_color("strong"), do: "bg-primary/10 text-primary ring-primary/20"

  def verification_status_color("moderate"),
    do: "bg-warning/10 text-warning ring-warning/20"

  def verification_status_color("weak"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  def verification_status_color(_), do: "bg-muted text-muted-foreground ring-border"

  def context_status_color("clean"), do: "bg-success/10 text-success ring-success/20"

  def context_status_color("degraded"),
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  def context_status_color(_), do: "bg-muted text-muted-foreground ring-border"

  def deploy_badge_class(true), do: "bg-success/10 text-success ring-success/20"

  def deploy_badge_class(_),
    do: "bg-warning/10 text-warning ring-warning/20"

  def risk_tier_pill_class("low"), do: "bg-success/10 text-success ring-success/20"

  def risk_tier_pill_class("moderate"), do: "bg-warning/10 text-warning ring-warning/20"

  def risk_tier_pill_class(tier) when tier in ["high", "critical"],
    do: "bg-destructive/10 text-destructive ring-destructive/20"

  def risk_tier_pill_class(_), do: "bg-muted text-muted-foreground ring-border"
end
