defmodule ControlKeel.Repo.Migrations.AddInvitationExpiryToMemberships do
  use Ecto.Migration

  def change do
    # Invitations previously never expired: a token disclosed years later (leaked
    # email, stale chat message) stayed a valid, unrevocable-by-time credential.
    # Nullable so existing pending invitations keep working and non-invite
    # memberships are unaffected.
    alter table(:memberships) do
      add :expires_at, :utc_datetime
    end
  end
end
