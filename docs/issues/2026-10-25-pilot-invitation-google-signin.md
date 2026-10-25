# Pilot invitation page offers no Google or GitHub sign-in

Date: 2026-10-25 · Environment: staging rehearsal of the pilot client pilot · Status: open

## What happened

The staging rehearsal of the Pro pilot invitation
([2026-10-20-client-pro-pilot.md](2026-10-20-client-pro-pilot.md))
sent invitation 1 to `justin@client.example`, an address with no
user yet. Justin opened the link, which showed the pilot page with only
"Create your password" fields, and signed in with Google instead. Google
sign-up ran the ordinary path: a new user, a Free "Justin Bowen's
Workspace", profile completion. The invitation stayed **Pending**, no
"the pilot client" workspace and no grant were created, and `/admin/pilots`
showed an empty access audit.

## Why

`WorkspaceInvitationsController#show` renders one of three states:

- signed in as someone else: sign out first;
- the invited address already has a user and nobody is signed in: a
  "Sign in to accept" link to `/session/new`, with
  `session[:return_to_after_authenticating]` set to the invitation path;
- otherwise: the accept form, with password fields when the user does not
  exist yet.

A new invitee therefore sees passwords only. The sign-in page (and the
Google and GitHub buttons on it) is reachable from the site header, but
the Google sign-up path redirects to `complete_profile_path` and never
reads the return path, so even a user who came from the invitation ends
up in a fresh Free workspace. The invitation token is still valid, so
reopening the link while signed in as the invitee shows the plain
"Accept invitation and open workspace" button and finishes the flow.
That is how the rehearsal was completed.

## Proposal

1. On the pilot (and teammate) invitation page, show "Continue with
   Google" and "Continue with GitHub" next to the password form when the
   invitee has no user yet, and next to "Sign in to accept" when they do.
   Both start the existing OAuth flows.
2. Set `session[:return_to_after_authenticating]` to the invitation path
   in `load_invitation` whenever nobody is signed in, not only for
   existing users.
3. In `GoogleSessionsController#sign_up` and the GitHub twin, honour the
   stored return path: when it points at a workspace invitation, create
   the user without `save_with_workspace` (the invitation creates the
   workspace) and redirect to the invitation instead of
   `complete_profile_path`. Name and `profile_completed` come from the
   provider profile as today.
4. `AcceptWorkspaceInvitation` already accepts a signed-in user whose
   email matches, so no change there. Add an integration test: new
   invitee signs up with Google from the invitation page, lands back on
   it, accepts, and owns exactly one workspace, the pilot one.
5. Until this ships, the invitation email and the admin's hand-off note
   should say "set a password on the invitation page; if you prefer
   Google, sign in first, then reopen the link".

## Log

- 2026-10-25: observed on staging (invitation 1, user created by Google
  sign-up with a Free workspace). Documented before Chris's production
  invitation goes out.
