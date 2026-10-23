# Local round trip: Sign in with Google and Sign in with GitHub

Goal: one real sign-up and one Settings connect/disconnect per provider on
`http://localhost:3000`, on the released 1.9.3 gems, before 1.9.4 and the
staging flips ([#213](https://github.com/activeagents/activeagents/pull/213)).

Worktree: `~/GitHub/activeagents-worktrees/signin-1.9.4` (branch
`test/signin-local-1.9.4`, from `origin/main` `6f17b8d`). It carries its own
`config/master.key` copy and is otherwise clean. Start it with:

```sh
cd ~/GitHub/activeagents-worktrees/signin-1.9.4
bin/rails server -p 3000 -b 127.0.0.1     # or bin/dev for the asset watchers too
```

Both services read their client from Rails credentials first and the
environment second (`app/services/google_sign_in.rb`,
`app/services/github_sign_in.rb`); `dotenv-rails` loads a `.env` in the
worktree root, and `.env` is gitignored. The provider buttons render only
when `configured?` is true, so a wrong or missing value shows up as a
missing button, not an error.

## 1. Google: a development OAuth client

Google Cloud console, project `active-agents-platform`, signed in as
`justin@activeagents.ai`:

1. **Google Auth Platform → Branding** (once per project): app name
   `Active Agent`, support and developer contact `hello@activeagents.ai`,
   authorized domain `activeagents.ai`. **Audience**: External, published.
   This is the same consent screen staging and production will use.
2. **Clients → Create client**, type **Web application**, name
   `ActiveAgents (local dev)`, authorized redirect URI
   `http://localhost:3000/auth/google/callback` (http, port included,
   nothing else). JavaScript origins empty.
3. On the client's page, **Download JSON** (the `client_secret_*.json`
   file lands in `~/Downloads`). Nothing is pasted anywhere.

Write the two values into the worktree's `.env` straight from that file,
then delete it:

```sh
cd ~/GitHub/activeagents-worktrees/signin-1.9.4
F=$(ls -t ~/Downloads/client_secret_*.json | head -1)
{
  printf 'GOOGLE_CLIENT_ID=%s\n'     "$(jq -r .web.client_id     "$F")"
  printf 'GOOGLE_CLIENT_SECRET=%s\n' "$(jq -r .web.client_secret "$F")"
} >> .env
rm "$F"
```

## 2. GitHub: the existing local-dev App

The org already has **ActiveAgents (local dev)**
(<https://github.com/organizations/activeagents/settings/apps/activeagents-local-dev>,
app id 5244252) with the **Email addresses: read-only** permission. In its
settings (sudo mode asks for the passkey first):

1. **General → Identifying and authorizing users → Callback URLs**: make
   sure `http://localhost:3000/auth/github/callback` is listed.
2. **General → Client secrets → Generate a new client secret**. The
   client ID is on the same page.
3. Append both to the same `.env`, typed at the prompt (nothing in shell
   history):
   ```sh
   read -r  GH_ID && printf 'GITHUB_APP_CLIENT_ID=%s\n' "$GH_ID" >> .env
   read -rs GH_SECRET && printf 'GITHUB_APP_CLIENT_SECRET=%s\n' "$GH_SECRET" >> .env
   unset GH_ID GH_SECRET
   ```

Restart Puma after editing `.env`.

## 3. Round trips

Check, each in a fresh private window so no session cookie carries over:

| # | Step | Expect |
| --- | --- | --- |
| 1 | `GET /session/new` and `/signup` | **Sign in/up with GitHub** and **with Google** render above the divider |
| 2 | Sign up with Google, a Google account with no user here | lands on profile completion, then plan selection; `users.signup_source = google`, `password_set = false`, one `user_identities` row with `provider = google`, `uid` = the `sub` |
| 3 | Sign out, sign in with the same Google account | signed straight in, returned to the page that asked |
| 4 | Sign up with GitHub, a GitHub account with a verified primary email and no user here | same shape with `signup_source = github`, `uid` = the numeric id, `login` = the GitHub login |
| 5 | Settings: disconnect Google on an account with no password and no GitHub | refused, with the **Email me a link to set a password** option |
| 6 | Settings: connect the other provider, then disconnect one | both allowed once two ways to sign in exist |
| 7 | A provider account whose email already has a password user | sent to the password sign-in, never auto-linked |
| 8 | Tamper: open `/auth/google` twice, finish the first | the stale `state` is refused, the second completes |

Record results below; screenshots go in a gitignored `tmp/` folder.

## Results

2026-10-22, 17:20 to 17:30 PDT, Chrome (Claude in Chrome) against the
worktree's Puma on `localhost:3000`, dev database
`activeagents_temp_development`. Set-up that day: consent screen created
(`Active Agent`, support `justin@activeagents.ai`, contact
`hello@activeagents.ai`, External, **Testing** status with test users
`justin@activeagents.ai` and `JusBowen@gmail.com`); clients
`ActiveAgents (local dev)` and `ActiveAgents (staging)`; a new client secret
on the `ActiveAgents (local dev)` GitHub App, whose localhost callback was
already registered. All four values went clipboard → `.env` (or Secret
Manager) by `pbpaste`; two of them still showed up in the session (see
"Exposure" below).

| # | Step | Result |
| --- | --- | --- |
| 1 | `/session/new` and `/registration/new` | **pass**: both buttons render above "or use your email" |
| 7 | Sign in with GitHub as TonsOfFun, whose primary email `JusBowen@gmail.com` already had a password user (id 4) | **pass**: back on `/session/new` with "An account already uses JusBowen@gmail.com. Sign in with your password, then connect GitHub from Settings."; no identity created |
| 4 | Same, after freeing the email (user 4 renamed for the test) | **pass**: user 10 created, `signup_source = github`, `password_set = false`, identity `github` / `TonsOfFun`; landed on `/complete_profile` with first and last name filled and the password optional |
| 5 | Settings on user 10 (no password, GitHub only) | **pass**: "You haven't set a password, so GitHub is the only way to sign in", **Email me a link to set a password**, "Set a password before you disconnect GitHub" in place of the button |
| 6a | Connect Google from Settings (account `jusbowen@gmail.com`) | **pass**: Google account chooser → consent page branded "Active Agent" → "Connected Google as jusbowen@gmail.com"; second identity row (`google`, `login` empty); **Disconnect GitHub** now enabled |
| 6b | Disconnect GitHub | **pass**: "Disconnected GitHub."; Google becomes the only way in, so its disconnect is refused |
| 3 | Sign out, Sign in with Google with the connected account | **pass**: no consent prompt the second time, signed straight in, returned to `/settings` |
| 2 | Sign out, Sign up with Google as `justin@activeagents.ai` (no user here) | **pass**: user 11 created, `signup_source = google`, `password_set = false`, identity `google`; `/complete_profile` with the name filled and the password optional |
| 8 | Tamper (stale `state`) | not run by hand; covered by `test/integration/sign_in_with_google_test.rb` |

Cleanup: users 10 and 11 and their workspaces destroyed, user 4's email
restored to `jusbowen@gmail.com`; the dev database is back to 5 users and
0 identities.

### Found and fixed

`app/views/onboarding/complete_profile.html.erb` said "You sign in with
GitHub" to a Google sign-up (hard-coded). It now names the providers the
user actually has (`to_sentence`), and both integration tests assert the
sentence after sign-up.

### Exposure

- The **first** GitHub client secret generated today
  (`…c3b66936`, "Never used") appeared in a screenshot. It is not the one
  in `.env` (a second one was generated and copied blind). Delete it on the
  App's Credentials page; the deletion was refused to the session.
- The `ActiveAgents (local dev)` Google client secret appeared in the
  accessibility tree of the "OAuth client created" dialog. **Rotated the
  same evening**: Justin added a second secret on the client's page and
  copied it, the session moved it from the clipboard into `.env` without
  reading it, Puma restarted, and a Google sign-in round trip succeeded on
  the new secret (code exchange and userinfo both fine). The first secret
  (`****QsDI`) is the one to disable or delete on the client page. The
  staging client's secret and the staging and second local-dev GitHub
  secrets were copied without being read.

### Change after review (2026-10-22 evening)

Justin: keep the never-auto-link rule (the squatter case above is the
reason), but the refusal should offer both ways forward. The notice on
`/session/new` now reads "An account already uses <email>. Sign in with
your password, or reset it with Forgot your password?, then connect
<Provider> from Settings." in both callback controllers; the tests assert
the new sentence and the docs describe it. Checked live with a Google
sign-in for `jusbowen@gmail.com` (existing password user): the notice
renders above the buttons, no identity is created. A first cut that
redirected to the password reset page with the address filled in was
reverted on Justin's "don't point at password reset, just suggest they
login or password reset".

### GitHub sign-up re-test (2026-10-23)

Justin: "we can test github by deleting my jusbowen@gmail.com?". User 4
(`jusbowen@gmail.com`, one empty workspace) was deleted from the dev
database, then Sign in with GitHub as `TonsOfFun`, whose primary GitHub
email is that address. Result: a fresh user (`signup_source` github,
`password_set` false, one GitHub identity), redirected to
`/complete_profile`, names filled from the profile, password optional,
copy "You sign in with GitHub." Pass. The dev database keeps today's three
test users (two Google sign-ups by Justin, this GitHub one); user 4 is
gone.

## Staging round trips (2026-10-23)

Driven with Claude in Chrome against `staging.activeagents.ai` (deploy of
`ee66a02`, #213; the #215 copy changes were not deployed yet). Staging
keeps its old data, so the long-standing `jusbowen@gmail.com` user (id 7)
was renamed to `jusbowen+old@gmail.com` with a `rails runner` on the
`activeagents-staging-migrate` job to free the address.

| Step | Result |
| --- | --- |
| Sign in with Google, address already a user | callback returned to `/session/new` with the existing-account notice (pre-#215 wording). Pass. |
| Sign in with GitHub, address already a user | same notice, `JusBowen@gmail.com` as GitHub reports it (matching is case-insensitive). Pass. |
| Sign up with Google, address free | user 375 created: verified, no password, `signup_source` google, one Google identity; landed on `/complete_profile` with names filled. Pass. The page said "You sign in with GitHub." (the bug #215 fixes). |
| Sign up with GitHub, address free (375 renamed to `jusbowen+google@gmail.com` first) | user 376 created: verified, no password, `signup_source` github, identity `TonsOfFun`; landed on `/complete_profile`. Pass. |

Not covered on staging: connect from Settings and disconnect (needs a
password sign-in, which the session cannot type; covered locally). Google
published-or-Testing is still unknown: every Google address used so far
is on the test-user list.

Staging now holds `jusbowen+old@gmail.com` (7, the original), 
`jusbowen+google@gmail.com` (375) and `jusbowen@gmail.com` (376, GitHub,
profile not completed). Rename or delete 375 and 376 before the next
sign-up test.
