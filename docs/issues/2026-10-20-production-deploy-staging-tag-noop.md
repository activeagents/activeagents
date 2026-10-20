# Production deploy of the `staging` tag is a no-op on repeat dispatches

Found 2026-10-20 while moving production to the 1.9.2 build after host
[#192](https://github.com/activeagents/activeagents/pull/192) merged.
Runbook: [production-environment.md](../infrastructure/production-environment.md);
the environment's history: [2026-10-20-production-full-stack.md](2026-10-20-production-full-stack.md).

## What happened

| Time (UTC) | Event |
|---|---|
| 20:22 | Production's first full deploy (run 39492120223, with the `staging` tag) created revision `activeagents-production-00007-jlr` from the then-current `staging` image, the `b6bb2ab` build |
| 21:03 | #192 merged; the staging deploy built `f4c65fb` and moved the `staging` tag to it; staging revision `00122-fvr` runs it from 21:10 |
| 21:15 | `deploy-production.yml` dispatched again with no `image_tag` (run 39498899781). Every job green: Terraform "1 to change" (a label on the Artifact Registry repository), migrate, smoke test |
| 21:17 | Production's latest ready revision is still `00007-jlr` from 20:22, digest `e4cf0222…`: the pre-1.9.2 image. The run reported success and changed nothing that matters |

## Why

The workflow passed `image=…/activeagents:staging` to Terraform, the same
string as the previous apply. Terraform saw no change to the Cloud Run
service template, so Cloud Run rolled no revision and kept serving the
digest it had resolved `staging` to at 20:22. Cloud Run never re-resolves a
tag on its own. The staging workflow does not have this problem because it
deploys `…:<commit sha>`, which changes on every build.

## Fix

`determine-image` now authenticates to Google Cloud and, when no
`image_tag` is given, resolves the `staging` tag to the commit tag that
`deploy-staging.yml` pushed beside it for the same digest (it tags every
build with both `<commit sha>` and `staging`). That commit tag is what
Terraform receives, so a repeat dispatch after a new main build rolls
production forward, and the deploy log names the commit being shipped. An
explicit `image_tag` is checked to exist in the registry before the apply.
The release path (a published release deploys its own tag, built by
`build-production`) is unchanged.

Verified locally under bash against the registry on 2026-10-20: the
`staging` tag's digest `e81033b9…` resolved to the commit tag
`b1dc0a08624db7335c8652e0c4d44dec710a702a`, the build that was being
deployed to staging at the time.

## Getting production onto 1.9.2 in the meantime

Run 39499460351, dispatched 21:19 UTC with
`image_tag=f4c65fb7627562fcab385fdd8ed90ad20e290417` (the #192 build that
staging runs), changes the image string and rolls a new revision. Its
result is recorded in the status paragraph of the runbook.

## Follow-up

- The smoke test only proves the service answers; a check that the latest
  ready revision's image digest matches the requested tag's digest would
  have turned run 39498899781 red. Worth adding when the workflow is next
  touched.
