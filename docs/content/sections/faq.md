---
# FAQ Section Configuration
layout: faq
---

# FAQ

Common questions about Active Agent

## Questions

### How do I install Active Agent?

Add `gem 'activeagent'` to your Gemfile and run `bundle install`.
Then run `rails generate active_agent:install` to set up the initial configuration.

### Which LLM providers are supported?

Active Agent supports OpenAI, Anthropic, Ollama, and OpenRouter. Switch providers with one line of code.

### Can I use Active Agent with existing Rails apps?

Yes! Active Agent is designed to integrate seamlessly with existing Rails applications. It works alongside your existing models, controllers, and services.

### What gems are included in the free tier?

The free tier includes the core `activeagent` and `solidagent` gems, `Action Prompt` for structured prompt management, generation provider modules (RubyLLM, OpenAI, Anthropic), plus built-in instrumentation, error handling, and retries. All free-tier gems are MIT licensed.

### What are the Pro tier gems?

Pro tier includes the Reasonable Reasons gems (Observable Evaluations, Observable Compliance, Deterministically Generative, Generally Deterministic, Generative UI, and Generative Generators), parallel tasks & retries, HITL generative UI with async triggers, and agentic workflows for multi-agent orchestration.

### What's the difference between Community and Pro?

The Community tier gives you full access to the open-source framework (ActiveAgent + SolidAgent gems) with all core features, modules, and community support. Pro ($99/mo or $995/yr) adds the Reasonable Reasons gem suite, parallel tasks, HITL generative UI, agentic workflows, hosted observability with trace dashboards, managed agent deployments, cost & latency analytics, LLM-as-judge evaluators, A/B prompt testing, and 48-hour email support SLA.

### What does Enterprise include?

Enterprise (starting at $2,995/yr) is for large organizations and regulated industries. It includes everything in Pro plus unlimited deployments and executions, 500,000+ traces with 400-day retention, advanced ML-powered anomaly detection, unlimited custom evaluators, SOC 2 Type II & HIPAA compliance, SSO/SAML & RBAC, private VPC deployment options, dedicated Slack channel, 4-hour email SLA, onboarding workshop, and quarterly architecture consultations.

### Is there a free trial for Pro?

Yes! Pro includes a 14-day free trial with no credit card required. You can explore all Pro features before committing.

### Can I self-host Active Agent?

Absolutely! The core framework is MIT licensed and can be self-hosted without limits on any tier. The hosted services (observability, evaluation, collaboration) are what differentiate the paid tiers.
