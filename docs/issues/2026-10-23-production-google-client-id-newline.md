# Production Google sign-in failed on first try: a newline in the client ID secret

**Date:** 2026-10-23
**Environment:** production (`activeagents.ai`), first deploy with
`enable_google_sign_in` on (#217, image `643879e`)
**Status:** fixed the same hour; hardening in the app follows in this PR

## What happened

The first Sign in with Google on activeagents.ai ended on Google's
"Access blocked: Authorization Error … Error 401: invalid_client. The
OAuth client was not found." page.

The client existed, the ID in Secret Manager matched the console, and a
hand-built authorize URL with the same ID reached Google's sign-in page.
Submitting the app's own form showed the difference: the app redirected
to Google with `client_id=336842002983-…googleusercontent.com%0A`. The
secret version carried a trailing newline, and `GoogleSignIn.client_id`
passed `ENV["GOOGLE_CLIENT_ID"]` through verbatim.

The shell comparison that "confirmed" the value hid the bug: `$(…)`
strips trailing newlines, so `[ "$actual" = "$expected" ]` passed. Only
`tail -c 1 | od -c` on the raw secret showed the `\n`. The other three
production sign-in secrets were clean (they were stored with
`printf '%s'` from the clipboard); the Google client ID was the one
typed from the console with an `echo`-style write.

## Fix

- `activeagents-production-google-oauth-client-id` version 2 added with
  `printf '%s' <id> | gcloud secrets versions add … --data-file=-`;
  version 1 disabled.
- Cloud Run resolves `latest` when an instance starts, so a new revision
  was rolled with `gcloud run services update … --update-secrets
  GOOGLE_CLIENT_ID=…:latest` (revision `activeagents-production-00013-m5d`).
  The spec is identical to what Terraform manages, so the next
  `Deploy to Production` converges without a diff worth acting on.
- Re-submitting the form sent a clean `client_id`; the browser round
  trip then passed (see the 1.9.4 plan status log).

## Hardening

`GoogleSignIn` and `GithubSignIn` now `strip` the four env-sourced
values before `presence`, so a secret stored with a stray newline or
space still works. Tests cover a value with surrounding whitespace.

## Rule going forward

Store every secret version with `printf '%s'` and never `echo`, and
verify the last byte with
`gcloud secrets versions access latest --secret <name> | tail -c 1 | od -c`
before the deploy that reads it. A `$(…)` comparison cannot catch this.
