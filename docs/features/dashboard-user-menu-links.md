# Host links in the dashboard's user menu

Date: 2026-10-25 · Status: shipped in actionagent 1.9.4; host repin PR open

## Ask

Justin (2026-10-25): "we should also give a way for users to get back into
the workspace admin level from the app settings dropdown or something."

The dashboard (the actionagent engine, mounted at `/dashboard`) owns the
product surface; the host owns the workspace pages (`/workspace`,
`/workspace/members`), how a user signs in (`/settings`) and the platform
administration (`/admin/pilots`). The engine header's avatar menu held one
item, "Sign out", so from the dashboard there was no way back to any of
those; the pilot layout's nav has them, but nothing in the dashboard
reaches that layout.

## Change

- **Gem** ([activeagents/activeagent#633](https://github.com/activeagents/activeagent/pull/633)):
  `ActionAgent.user_menu_links`, an Array of `{ label:, href: }` or a Proc
  receiving `(user, owner)`; `DashboardController#meta_props` passes the
  resolved list as `userMenuLinks`, and `Header.jsx` lists it above "Sign
  out". Blank or non-`/`/`http(s)` hrefs are dropped; a raising Proc is
  logged and yields nothing, so the seam cannot take the dashboard down.
  Self-hosted installs leave it unset and see the menu they had.
- **Host** (this branch): `config/initializers/action_agent.rb` sets the
  Proc to Workspace, Members, Account settings, and Platform admin for
  verified admins. It is wrapped in `respond_to?(:user_menu_links=)` so the
  app keeps booting on actionagent 1.9.3; the menu appears once the Gemfile
  pins 1.9.4.

## Follow-up

- Done 2026-10-25: gem #633 merged, released as actionagent 1.9.4 (tag
  `v1.9.4`, release PR #634); the host repin is branch `chore/repin-1.9.4`.
  `bin/rails runner` on the repinned host resolves Workspace, Members,
  Account settings, Platform admin for an admin and the first three for a
  member.
- Chrome check on staging after the deploy: avatar menu shows the four
  items for `justin@activeagents.ai`, three for a non-admin.
