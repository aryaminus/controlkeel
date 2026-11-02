defmodule ControlKeelWeb.ScopeError do
  @moduledoc """
  Shared error payload for URL-scoped pages.

  Invalid routes retain the deepest scope that resolves and is accessible:

    * `/:org_slug` — global organization not-found page.
    * `/:org_slug/typo` and `/:org_slug/workspaces/:unknown_ws` — organization
      navigation.
    * `/:org_slug/workspaces/:ws_slug/typo` and
      `/:org_slug/workspaces/:ws_slug/sessions/:unknown_id` — workspace
      navigation.
    * `/:org_slug/workspaces/:ws_slug/sessions/:id/typo` — session navigation,
      but only when that session resolves and is accessible.

  Missing and inaccessible resources use the same public not-found response.
  The organization layout renders the error panel in place, and the browser
  uses `:invalid_root` to clear a stale `ck.lastPath` value.

  `:needs_admin` deliberately leaves `:invalid_root` empty: the visitor is a
  member and can still use the parent scope, so the saved scope root remains
  valid. Not-found and forbidden errors invalidate the whole scope root.
  """

  @type scope :: :org | :workspace | :session | :url

  @type kind :: :not_found | :forbidden | :needs_admin | :membership_changed

  @type t :: %{
          required(:kind) => kind(),
          required(:scope) => scope(),
          required(:title) => String.t(),
          required(:message) => String.t(),
          required(:scope_root) => String.t() | nil,
          required(:invalid_root) => String.t() | nil,
          required(:parent_path) => String.t() | nil,
          required(:parent_label) => String.t() | nil,
          required(:org_slug) => String.t() | nil,
          required(:ws_slug) => String.t() | nil,
          required(:session_id) => integer() | String.t() | nil
        }

  @spec org(String.t() | nil, kind()) :: t()
  def org(slug, kind \\ :not_found) do
    root = org_root(slug)

    %{
      kind: kind,
      scope: :org,
      title: org_title(kind),
      message: org_message(kind),
      scope_root: root,
      invalid_root: invalid_root(kind, root),
      parent_path: nil,
      parent_label: nil,
      org_slug: slug,
      ws_slug: nil,
      session_id: nil
    }
  end

  @spec url(String.t() | nil, list() | String.t() | nil, kind()) :: t()
  def url(org_slug, path, kind \\ :not_found) do
    root = org_root(org_slug)

    path_suffix =
      case path do
        list when is_list(list) -> Enum.join(list, "/")
        str when is_binary(str) -> str
        _ -> ""
      end

    invalid = if root && path_suffix != "", do: "#{root}/#{path_suffix}", else: root

    %{
      kind: kind,
      scope: :url,
      title: "Can't find the page",
      message:
        "We can't find the page you're looking for, or you don't have permission to view it.",
      scope_root: root,
      invalid_root: invalid_root(kind, invalid),
      parent_path: root,
      parent_label: "organization",
      org_slug: org_slug,
      ws_slug: nil,
      session_id: nil
    }
  end

  @spec workspace(String.t() | nil, String.t() | nil, kind()) :: t()
  def workspace(org_slug, ws_slug, kind \\ :not_found) do
    root = workspace_root(org_slug, ws_slug)

    %{
      kind: kind,
      scope: :workspace,
      title: workspace_title(kind),
      message: workspace_message(kind),
      scope_root: root,
      invalid_root: invalid_root(kind, root),
      parent_path: org_root(org_slug),
      parent_label: if(org_root(org_slug), do: "organization"),
      org_slug: org_slug,
      ws_slug: ws_slug,
      session_id: nil
    }
  end

  @spec session(String.t() | nil, String.t() | nil, integer() | String.t() | nil, kind()) :: t()
  def session(org_slug, ws_slug, session_id, kind \\ :not_found) do
    root = session_root(org_slug, ws_slug, session_id)

    %{
      kind: kind,
      scope: :session,
      title: session_title(kind),
      message: session_message(kind),
      scope_root: root,
      invalid_root: invalid_root(kind, root),
      parent_path: workspace_root(org_slug, ws_slug),
      parent_label: "workspace",
      org_slug: org_slug,
      ws_slug: ws_slug,
      session_id: session_id
    }
  end

  @doc """
  Error assigned when a live membership change invalidates the open page.
  """
  @spec membership_changed(scope(), t()) :: t()
  def membership_changed(scope, previous) do
    %{
      previous
      | kind: :membership_changed,
        title: "Access changed",
        message: membership_message(scope),
        invalid_root: previous.scope_root
    }
  end

  defp invalid_root(:needs_admin, _root), do: nil
  defp invalid_root(_kind, root), do: root

  defp org_root(nil), do: nil
  defp org_root(slug) when is_binary(slug) and slug != "", do: "/#{slug}"
  defp org_root(_slug), do: nil

  defp workspace_root(org_slug, ws_slug) do
    case {org_root(org_slug), ws_slug} do
      {nil, _ws_slug} ->
        nil

      {org_root, ws_slug} when is_binary(ws_slug) and ws_slug != "" ->
        "#{org_root}/workspaces/#{ws_slug}"

      _ ->
        nil
    end
  end

  defp session_root(org_slug, ws_slug, session_id) do
    case workspace_root(org_slug, ws_slug) do
      nil ->
        nil

      workspace_root when is_binary(session_id) or is_integer(session_id) ->
        "#{workspace_root}/sessions/#{session_id}"

      _ ->
        nil
    end
  end

  defp org_title(:needs_admin), do: "Organization unavailable"
  defp org_title(_kind), do: "Organization not found"

  defp org_message(:needs_admin),
    do: "You don't have permission to access this part of the organization."

  defp org_message(_kind),
    do: "No organization exists at this address. It may have been renamed or deleted."

  defp workspace_title(_kind), do: "Can't find the page"

  defp workspace_message(_kind),
    do: "We can't find the page you're looking for, or you don't have permission to view it."

  defp session_title(_kind), do: "Can't find the page"

  defp session_message(_kind),
    do: "We can't find the page you're looking for, or you don't have permission to view it."

  defp membership_message(:org),
    do: "Your access to this organization changed."

  defp membership_message(:workspace),
    do: "Your access to this workspace changed."

  defp membership_message(:session),
    do: "Your access to this session changed."

  defp membership_message(:url),
    do: "Your access to this page changed."
end
