# Workspace members

A workspace (`Account`) has members through `AccountMembership`, each with one role:

| Role | Can |
|------|-----|
| owner | everything an admin can, and remove another owner. Created only with the workspace. |
| admin | invite admins and members, revoke and resend invitations, change roles between admin and member, remove admins and members |
| member | see the member list and pending invitations |

Members manage the team at `/workspace/members`, linked from `/workspace` and the header.

## Invitations

Teammate invitations reuse `WorkspaceInvitation`. A row with a `role` is a teammate invitation into its `account`. A row without one is a [pro pilot](pro-pilots.md) invitation, and the pilot admin pages only see those.

- The inviter picks `admin` or `member` when sending. Acceptance never reads a role from the request.
- Sending creates the row and queues `WorkspaceInvitationDeliveryJob`, which mints the token, stores its SHA-256 digest with a 7-day expiry and sends `TeammateMailer#invitation`. Resending rotates the token. Revoking clears it.
- Accepting requires a signed-in user whose verified email equals the invited email, ignoring case. The link alone never creates a user. Someone without an account signs up and verifies first, then reopens the link.
- Acceptance locks the workspace, then the invitation, and consumes the token in the same transaction, so a link works once.
- A link stops working when its sender is no longer an owner or admin. Removing or demoting an admin revokes the invitations they sent.
- Sends (new and resent) are limited to 20 per workspace per hour. Requests refused because the sender isn't an owner or admin don't count.

## Seats

`Plan#included_seats` (-1 for unlimited) caps members plus teammate invitations that are outstanding, unexpired and not failed (an invitation whose email failed to send frees its seat until it is resent). Sending, resending and accepting all check it under the workspace lock. A resend needs a free seat, not counting the invitation being resent. A workspace over its limit, after a downgrade for example, can't resend a pending invitation, which couldn't be accepted anyway. Free includes one seat, which is the owner's, so inviting needs a paid plan.

## Removing a member

An owner or admin removes a member from `/workspace/members`. In the same transaction:

- the API keys the member created in the workspace (`api_keys.user_id`) are deleted,
- invitations they sent and that are still outstanding are revoked,
- their sessions stop selecting the workspace.

After commit, their Action Cable connections opened for the workspace are disconnected. Only an owner can remove an owner, and the last owner and the billing owner (`Account#owner`) can't be removed.

Known gaps:

- The 1.7 engine does not write `api_keys.user_id`, so keys created through the dashboard today carry no creator and survive a removal. Removal deletes them once the engine records the creator. Until then the members page tells managers to revoke keys by hand under Settings → API Keys; reword that note when the engine change ships.
- The workspace's telemetry key (`accounts.telemetry_api_key`) is shown to every member in the dashboard and authenticates trace ingest. Removal doesn't rotate it, and nothing in the app rotates it yet.
- Provider keys are workspace-wide. There are no personal provider keys to delete yet.
- Engine permission checks (who may manage provider keys, API keys and the GitHub connection) still allow every member.
