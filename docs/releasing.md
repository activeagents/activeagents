# Releasing the platform

The platform ships as a container image, `ghcr.io/activeagents/activeagents`,
versioned after the agent gems it runs. Customers run a tagged image in their
own environment, and activeagents.ai runs the newest one.

## Versions

| Tag | Means |
| --- | --- |
| `v1.8.1` | this app on activeagent and actionagent 1.8.1 |
| `v1.8.1.1`, `v1.8.1.2` | platform-only releases on those same gems |

The Gemfile pins `activeagent` and `actionagent` exactly, and takes them,
`solid_agent` and `activeagents-telemetry` from RubyGems. `bin/release check`
refuses a tag the lock does not match, and a lock that takes any of those
from git or a path, so every published image rebuilds from released gems.

```sh
bin/release next          # the tag to push for the current lock
bin/release check v1.8.1  # what release.yml checks first
bin/release gems          # the agent gem versions the lock runs
```

## From a gem release to a platform release

1. **The gem repository releases.** A `v*` tag on activeagents/activeagent
   publishes both gems. Its last job dispatches `agent-gems-released` here
   with their versions.
2. **A pull request moves the pins.** `.github/workflows/agent-gems.yml`
   waits for RubyGems to serve both versions, moves the two pins, relocks
   conservatively, and opens a pull request named "Run activeagent and
   actionagent X.Y.Z". Run that workflow by hand to catch up on a release.
3. **Mirror the engine's migrations.** The pull request lists the engine's
   generator templates that changed. This app mounts the engine with
   `table_name_prefix = ""`, so each new migration template needs a migration
   in `db/migrate` written against the unprefixed tables, and `db/schema.rb`
   updated. This is the one step a person has to do.
4. **Merge, then tag.**

   ```sh
   git checkout main && git pull
   tag=$(bin/release next)
   git tag "$tag" && git push origin "$tag"
   ```

A platform-only change needs no gem release: merge it, then push the tag
`bin/release next` prints, which is the next `.N` on the current gems.

## What the tag runs

`.github/workflows/release.yml`, in order:

1. **version** runs `bin/release check` on the tag.
2. **ci** runs the pull request checks: security scan, lint, production
   eager load, and the test suite.
3. **image** builds linux/amd64 and linux/arm64 on native runners and pushes
   each by digest.
4. **publish** tags the multi-architecture image with its full version, its
   gem version, its minor line and `latest`. Each alias moves only while
   this is the newest release in its line, so re-running an old tag never
   moves one backwards.
5. **release** creates the GitHub release with notes naming the gem
   versions, and attaches `compose.yml` with this version as its default.
6. **production** calls `deploy-production.yml` for the newest release only.

A release created with `GITHUB_TOKEN` raises no `release` event, so
production deploys through that call. Publishing a release by hand in the
GitHub UI creates its tag, and the tag runs the same workflow. To re-run a
release, dispatch Release from the tag (Use workflow from: Tags).

## One-time setup

- **`PLATFORM_RELEASE_TOKEN`**, a fine-grained token with Contents and Pull
  requests read/write on activeagents/activeagents, as an organization
  secret available to both repositories. activeagent's release workflow
  needs it to dispatch here, and skips that step without it. Here it opens
  the bump pull request as a user, which is what lets CI run on it; without
  it the pull request opens with `GITHUB_TOKEN` and says CI has to be
  started by hand.
- **Make the package public** after the first release publishes it: the
  organization's Packages page, `activeagents`, Package settings, Change
  visibility. GitHub creates container packages private.
