# Organization Membership

## Invitation Flow

```
Admin/Owner invites by email
    → User record created (if new)
    → Membership: status=pending, invitation_token_hash=set
    → Raw token shown once + emailed

Invitee opens /invitations/:token
    → Sees org name + role
    → Not authenticated → "Continue with Google/GitHub"
    → OAuth → redirected back to invitation page
    → Email matches → "Accept"
    → status=active, token_hash=cleared, accepted_at=stamped
```

- Token is 256-bit random, stored as SHA-256 hash (not reversible).
- Token hash is cleared on both accept and revoke.
- Acceptance requires OAuth — token proves _what_ (org + role), OAuth proves _who_ (email).

## Re-inviting Revoked Members

| Existing state       | Behavior                           |
| -------------------- | ---------------------------------- |
| None                 | INSERT new pending membership      |
| `revoked`            | UPDATE to pending with fresh token |
| `active` / `pending` | `{:error, :already_member}`        |

## Revoke Rules

| Who is being revoked | Owner can revoke? | Admin can revoke? | Member can revoke? | Viewer can revoke? |
| -------------------- | ----------------- | ----------------- | ------------------ | ------------------ |
| Owner                | Yes\*             | No                | No                 | No                 |
| Admin                | Yes               | No                | No                 | No                 |
| Member               | Yes               | Yes               | No                 | No                 |
| Viewer               | Yes               | Yes               | No                 | No                 |

\*Owner cannot revoke self if they are the last owner.

Enforced at two layers: UI (`can_revoke?/3`) hides the button, server (`revoke_membership/2`) rejects unauthorized calls.

## Role Change Rules

Server enforcement lives in `update_membership_role/3` (`accounts.ex`). The UI mirrors those rules in `role_select_state/4` (`organization_detail_live.ex`) so the dropdown only ever offers legal choices: rows the viewer can't change render a **disabled** select, and options the viewer can't grant are simply omitted. There is no client-side JS hook; the server remains the authoritative layer and rejects anything the UI fails to hide.

### Matrix

| Revoker  | Self                           | Other owner               | Other admin               | Member / Viewer           |
| -------- | ------------------------------ | ------------------------- | ------------------------- | ------------------------- |
| Owner    | Any role, except if last owner | Any role                  | Any role                  | Any role                  |
| Admin    | Demote to member/viewer only   | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | member or viewer only     |
| Member   | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |
| Viewer   | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |
| Outsider | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |

### Rules

1. **Only admins and owners see the role dropdown.** Members/viewers see the role as plain text (`@can_manage` is `false`).
2. **Only owners can grant admin or owner.** Admins cannot promote anyone (including self) to admin or owner.
3. **Admins can demote themselves** to member or viewer, but cannot otherwise touch other admins or owners.
4. **Admins can move members/viewers laterally** between the member and viewer roles only.
5. **The last active owner is protected.** An owner cannot demote themself if no other active owner exists (`:last_owner_protected`). Promote another member first, then demote.
6. **No-op selections are allowed.** Selecting the current role succeeds without error (does not trigger promotion checks).
7. **UI gating.** The member table renders the `<select>` server-side via `role_select_state/4`, which disables the control (owner/admin rows for an admin viewer; the last owner's own row) or withholds options (admin viewer only sees member/viewer for non-privileged rows; the admin's own row adds admin as the current value plus member/viewer to step down). The viewer's own role and `@can_manage` are rebound on every change via `refresh_memberships/2`, so a self-demotion instantly collapses the management UI (selects become plain text, Revoke/Invite buttons vanish) without a reload.

### Error Codes

| Error                   | Cause                                                                |
| ----------------------- | -------------------------------------------------------------------- |
| `:unauthorized`         | Revoker lacks permission for the target or new role.                 |
| `:last_owner_protected` | Owner attempted to demote self while they are the last active owner. |
| `:invalid_role`         | `new_role` is not one of `owner`, `admin`, `member`, `viewer`.       |
| `:not_found`            | `membership_id` does not exist.                                      |

## Invite Authorization

`invite_member/3` enforces the same privilege boundary as role changes **when an inviter is named** (`invited_by_user_id`):

- **Owner** may invite at any role (owner/admin/member/viewer).
- **Admin** may invite only member/viewer. Granting owner or admin returns `{:error, :unauthorized}`.
- A `nil` inviter is the trusted operator path (the CLI `org invite` command, which has no membership) and is unrestricted.
- The web invite modal withholds owner/admin from the role dropdown for non-owners via `invite_role_options/1`, matching the server guard.

This closes the gap where an admin could otherwise grant owner/admin by inviting a brand-new user (which the role-change matrix forbids for existing members).

## Live Eviction and Role Refresh

There is no ambient "current org". Every page resolves the org it renders from
its own URL, so `ControlKeelWeb.LiveAuth` refreshes and evicts per page:

- **Org-scoped pages** (`/:org_slug`, `/:org_slug/settings`) resolve the
  visitor's membership for the URL org and keep it in `:current_membership`.
- **Workspace-scoped pages**
  (`/:org_slug/workspaces/:ws_slug/...`) resolve authority from
  `(user, workspace.org_id)` through `ControlKeelWeb.WorkspaceScope`, which
  wraps `ControlKeelWeb.WorkspaceAccess.check_membership/3` and assigns the
  same `:current_membership`.

`LiveAuth` subscribes each connected socket to `membership:user:<id>` and
reacts to `{:membership_changed, %Membership{}}`:

| Event                                                        | Result                                                                |
| ------------------------------------------------------------ | --------------------------------------------------------------------- |
| Revocation of the page's membership                           | Redirect to `/organizations` with an info flash — never a sign-out.    |
| Role change in the page's organization                        | `:current_membership` is reassigned in place; permission-derived UI re-renders without a reload. |
| Change in an unrelated organization                           | No-op; the page is unaffected.                                        |
| Revocation that removes the visitor's last active membership  | Redirect to `/organizations` with a different flash.                  |
| `:sign_out_everywhere`                                        | Redirect to `/auth/login`.                                            |

Server-side gates stay authoritative: event handlers re-check the database
(`WorkspaceAccess.check/3`), while render-time controls derive from the
refreshed membership (`WorkspaceAccess.can_mutate?/1`), so a demotion collapses
the controls and the event is still denied if it is triggered directly.

On `push_patch` the LiveView process survives the URL change, so
`WorkspaceScope.refresh/2` re-runs the workspace gate when `org_slug`/`ws_slug`
change and the page reloads its data for the new workspace. Without it a
workspace switch would keep rendering the previous workspace's data — and the
previous organization's membership — under the new URL.
