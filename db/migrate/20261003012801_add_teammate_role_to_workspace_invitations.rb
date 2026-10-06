class AddTeammateRoleToWorkspaceInvitations < ActiveRecord::Migration[8.2]
  def change
    add_column :workspace_invitations, :role, :string
    change_column_null :workspace_invitations, :reason, true
    change_column_null :workspace_invitations, :review_on, true

    add_check_constraint :workspace_invitations, "role IS NULL OR role IN ('admin', 'member')",
      name: "workspace_invitations_role_allowed"
    add_check_constraint :workspace_invitations, "role IS NULL OR account_id IS NOT NULL",
      name: "workspace_invitations_teammate_account"

    # A pilot invitation creates the invitee's own workspace, so its pending
    # email stays unique platform-wide. A teammate invitation is unique per
    # workspace: the same person can be invited into several.
    remove_index :workspace_invitations, :email_address, unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_pending_invitation_email"
    add_index :workspace_invitations, :email_address, unique: true,
      where: "role IS NULL AND accepted_at IS NULL AND revoked_at IS NULL", name: "index_pending_pilot_invitation_email"
    add_index :workspace_invitations, [ :account_id, :email_address ], unique: true,
      where: "role IS NOT NULL AND accepted_at IS NULL AND revoked_at IS NULL", name: "index_pending_teammate_invitation_email"
  end
end
