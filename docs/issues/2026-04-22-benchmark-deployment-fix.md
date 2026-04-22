# Benchmark Deployment Fix

**Date:** 2026-04-22
**Issue:** Staging deployments failing - ragents benchmarks not working in production

## Problems Identified

### 1. Docker Build Failure - Missing ragents directory

The Docker build was failing because the `ragents` gem (a path dependency) wasn't available when `bundle install` ran.

**Error:**
```
The path `/rails/ragents` does not exist.
```

### 2. Ruby Version Mismatch

The ragents gemspec required Ruby 4.0+ but production uses Ruby 3.4.8.

**Error:**
```
ragents-0.1.0 requires ruby version >= 4.0.0, which is incompatible with the current version, 3.4.8
```

### 3. Ractor Hang in Cloud Run

Ractors are experimental in Ruby 3.4 and hang/crash in Cloud Run. The BenchmarkRunnerService was using Ractors even for sequential/thread benchmarks.

## Solutions

### Fix 1: Dockerfile - Copy ragents before bundle install

```dockerfile
COPY Gemfile Gemfile.lock ./
COPY ragents/ ragents/
RUN bundle install && ...
```

Also updated Ruby version from 3.4.1 to 3.4.8.

### Fix 2: Lower ragents Ruby requirement

Changed `ragents/ragents.gemspec`:
```ruby
spec.required_ruby_version = ">= 3.2.0"  # was ">= 4.0.0"
```

### Fix 3: Direct provider calls for non-Ractor strategies

Updated `BenchmarkRunnerService#run_agent` to use direct provider calls instead of `AgentRactor` for sequential/thread benchmarks.

### Fix 4: Disable Ractors by default in Cloud Run

Updated `Api::BenchmarksController#run` to detect Cloud Run via `K_SERVICE` env var and disable Ractors by default.

## Related Commits

- `18de797` - feat(benchmarks): Add cloud benchmark runner for ragents
- `5db5375` - fix(docker): Copy ragents directory before bundle install
- `470bb34` - fix(ragents): Lower Ruby version requirement from 4.0 to 3.2
- `fd5c309` - fix(benchmarks): Use direct provider calls for non-Ractor strategies
- `a96c0a6` - fix(benchmarks): Disable Ractors by default in Cloud Run

## Testing

1. Deploy to staging: `staging.activeagents.ai`
2. Test endpoint: `curl -X POST https://staging.activeagents.ai/api/benchmarks/run`
3. Verify benchmarks render on `/dashboard/benchmarks`
4. Can explicitly enable Ractors: `?include_ractors=true`
