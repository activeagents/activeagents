# Clean lists for production: the staging database and the Resend segments

Date: 2026-10-20 · Status: findings and commands ready; deletions are Justin's to run · Follows [2026-10-20-email-sender-reputation.md](2026-10-20-email-sender-reputation.md) step 1

## What is actually polluted

Checked 2026-10-20 (Resend through its API with the staging key; the live
database through a read-only `rails runner` on `activeagents-staging-migrate`,
execution `tv2vw`).

**The Resend contact list is clean of the bot.** The app has
`SyncUserToResendJob` but nothing enqueues it, so signups never reach Resend;
only confirmed newsletter subscriptions do. No contact was created after
2026-09-02.

| Resend segment | Contacts | What they are |
|---|---|---|
| Users | 12 | 6 real-looking addresses, 6 test entries (`+landercheck`, `+resendcheck`, `+agent`, `ssss@sss.com`, `test…@example.com`, two `haxorsistz…` strings) |
| Newsletter | 816 | the Mailchimp import of 2026-03-28, never confirmed on this platform |
| General | 0 | unused |
| no segment | 1 | one `+resendcheck` test contact |

Suppressions: one complaint (a Comcast address, 2026-10-19) and one old
bounce. Both stay.

**The live database carries the bot.** Users by creation date:

| | Count |
|---|---|
| users in total | 370 |
| created since 2026-10-17 (all `public_signup`) | 344 (Oct 17: 24, Oct 18: 77, Oct 19: 174, Oct 20: 69) |
| of those, unverified | 338 |
| of those, verified but never completed a profile | 6 (3 with no password at all: link-scanner clicks) |
| workspaces owned by those 344 | 344 (every signup creates one) |
| users from before Oct 17 | 26, of which 16 unverified (old test signups) |
| profile completed, ever | 9 |
| newsletter rows | 1, unconfirmed, from the bot's probe |

So "clean" means 26 to 32 users, not 370.

## The clean-up, in order

### 1. Database: delete the bot's users (Justin runs)

Dry run first. It prints the count that would go and lists the six
verified-but-unfinished users for a look, since one of them could be a
person who clicked the link and stopped:

```sh
gcloud run jobs execute activeagents-staging-migrate --region=us-central1 --project=active-agents-platform --wait \
  --args='^~^runner~since = Time.utc(2026, 10, 17); recent = User.where("created_at >= ?", since).where(signup_source: "public_signup", profile_completed: false); puts "DRY would delete #{recent.where(email_verified: false).count} unverified users and their workspaces"; recent.where(email_verified: true).find_each { |u| puts "REVIEW #{u.id} created=#{u.created_at.to_date} password_set=#{u.password_set} sessions=#{u.sessions.count} #{u.email_address}" }'
```

Read the output (replace the execution name the command printed):

```sh
gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="activeagents-staging-migrate" AND labels."run.googleapis.com/execution_name"="activeagents-staging-migrate-XXXXX"' --project=active-agents-platform --limit=100 --format='value(textPayload)' | grep -E '^(DRY|REVIEW)'
```

Then the deletion of the unverified ones. `destroy!` cascades through
sessions, memberships and the owned workspace (its traces, keys and grant);
no bot workspace holds a pilot invitation, which is the one association that
would refuse:

```sh
gcloud run jobs execute activeagents-staging-migrate --region=us-central1 --project=active-agents-platform --wait \
  --args='^~^runner~since = Time.utc(2026, 10, 17); doomed = User.where("created_at >= ?", since).where(signup_source: "public_signup", profile_completed: false, email_verified: false); puts "DELETING #{doomed.count}"; doomed.find_each { |u| u.destroy! }; puts "LEFT since Oct 17: #{User.where("created_at >= ?", since).count}; users total: #{User.count}; accounts total: #{Account.count}"'
```

Expected: `DELETING 338`, then 6 left since Oct 17 and 32 users in total.
The six reviewed ones go the same way with `email_verified: true` in place
of `false` once judged; the 16 pre-Oct-17 unverified test signups and the
one unconfirmed newsletter row (`NewsletterSubscription.where(confirmed_at: nil).destroy_all`)
are an optional second pass.

### 2. Resend: drop the test contacts (Justin runs)

Seven contacts, by ID, with the staging key (the production key reaches
the same account):

```sh
KEY=$(gcloud secrets versions access latest --secret=activeagents-staging-resend-api-key --project=active-agents-platform)
for id in a02917d5-fc4f-45bc-95e3-b454f618470d cff571bf-c094-4d77-9a5b-b6efbe1cc710 ffdea9b4-66db-407a-b3fb-3d689709d999 5a998a03-8f6d-4c09-8e5a-ab3dfc79ba7c db048fff-ad02-4e36-a95f-892e82704e40 68d1bf9a-e316-4c25-b52c-2d7a7fa295e0 f78c61c1-f67a-4acf-ad7a-78d6637513b2; do
  curl -sS -X DELETE -H "Authorization: Bearer $KEY" "https://api.resend.com/contacts/$id"; echo
done
unset KEY
```

The Users segment then holds the six real addresses. The two complaint and
bounce suppressions stay as they are.

### 3. The Newsletter segment: decide before the first broadcast

816 addresses imported from Mailchimp seven months ago, none of which
confirmed anything on this platform, are the biggest reputation risk left
once the bot is gone: a first broadcast to a cold imported list is where
complaint rates jump. Options, best first:

1. A one-time re-permission send from the verified `activeagents.ai`
   domain once it exists, with one-click unsubscribe, and keep only the
   addresses that click; the rest leave the segment.
2. Keep the list, but send the first newsletters in slices of about a
   hundred and watch complaints and unsubscribes in Resend before the next
   slice.
3. Do nothing until the Postmaster Tools reputation reads at least Medium.

Either way the newsletter needs `List-Unsubscribe` headers before any
broadcast (step 5 of the reputation plan).

### 4. Production: which lists it uses (Justin decides; the assistant wires it)

Resend is one account for both environments; the segments are shared.
Production's `RESEND_AUDIENCE_ID` and `RESEND_NEWSLETTER_AUDIENCE_ID` should
name the same two segments as staging (checked below), so nothing is
"migrated" in Resend at the cutover: the clean segments are the production
segments.

For the database, the cutover decides whether production starts from a copy
of the cleaned staging database or empty. Either way, clean first.

Because the app never syncs users to Resend, the Users segment is a manual
list today. If production should keep it current, the one sensible wiring is
to enqueue `SyncUserToResendJob` when a profile is completed (verified
address, a person who finished signing up), never at signup. That is a
small code change the assistant can make on request; it is deliberately not
in [#180](https://github.com/activeagents/activeagents/pull/180).

## Who does what

- The assistant: exported and classified the contacts, counted the
  database, wrote the commands above, and can create segments, import
  clean contacts and wire the profile-completed sync on request.
- Justin: runs the deletions in steps 1 and 2 (they are permanent, so they
  are not the assistant's to run), and decides step 3.

## Log

- 2026-10-20: Resend export (828 contacts, 9 pages) to the session
  scratchpad; database counts via execution `activeagents-staging-migrate-tv2vw`.
