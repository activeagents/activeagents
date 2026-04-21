# Benchmark Deployment Fix

**Date:** 2026-04-22
**Issue:** Staging deployments failing - ragents benchmarks not working in production

## Problem

The Docker build was failing because the `ragents` gem (a path dependency) wasn't available when `bundle install` ran.

**Error:**
```
The path `/rails/ragents` does not exist.
```

The Dockerfile was copying files in this order:
1. `COPY Gemfile Gemfile.lock ./`
2. `RUN bundle install` - **Failed here** because ragents/ doesn't exist
3. `COPY . .` - too late!

## Root Cause

The Gemfile contains:
```ruby
gem "ragents", path: "ragents"
```

This path dependency requires the ragents directory to exist before bundle install runs.

## Solution

Modified `Dockerfile` to copy the ragents directory before running bundle install:

```dockerfile
# Install application gems
# Copy ragents directory first since it's a path dependency in Gemfile
COPY Gemfile Gemfile.lock ./
COPY ragents/ ragents/
RUN bundle install && \
    ...
```

Also updated Ruby version from 3.4.1 to 3.4.8 to match `.ruby-version`.

## Affected Components

- `/api/benchmarks/run` endpoint - triggers cloud benchmark execution
- `BenchmarkRunnerService` - runs ragents concurrency benchmarks
- Dashboard Benchmarks page - displays results

## Testing

1. Commit and push to trigger GitHub Actions deployment
2. Monitor staging deployment at `staging.activeagents.ai`
3. Test endpoint: `POST /api/benchmarks/run`
4. Verify benchmarks render on `/dashboard/benchmarks`

## Related Commits

- `18de797` - feat(benchmarks): Add cloud benchmark runner for ragents
- This fix - fix(docker): Copy ragents directory before bundle install
