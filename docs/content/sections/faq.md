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

### What gems are included in the free tier?

The free tier includes the Active Agent gem, Action Prompt, and all Generation Provider modules (RubyLLM, OpenAI, Anthropic — both official and community gems). You also get Instrumentation, Error Handling, and Retries modules at no cost.

### Which Generation Providers are supported?

Active Agent supports multiple providers through its Generation Providers module: RubyLLM, OpenAI (official and community gems), Anthropic (official and community gems), Ollama, and OpenRouter. Switch providers with one line of code.

### What are the Reasonable Reasons gems in Pro?

The Reasonable Reasons gems are Pro-tier modules that include Observable Evaluations, Observable Compliance, Deterministically Generative, Generally Deterministic, Generative UI, and Generative Generators (with self-healing capabilities). These gems add advanced analytics and generative capabilities to your agents.

### What's the difference between Community and Pro?

The Community (Dev) tier gives you full access to the open-source Active Agent gem, Action Prompt, all Generation Providers, and core modules (Instrumentation, Error Handling, Retries) — free forever. Pro ($99/mo or $995/yr) adds the Reasonable Reasons gems, HITL generative UI, parallel tasks & retries, agentic workflows with pausable multi-agent actions, async tasks with external triggers, hosted observability, and 48-hour email support SLA.

### What are agentic workflows?

Agentic workflows in the Pro tier allow you to break complex tasks into many agents' actions, which can be paused between tasks. Combined with HITL generative UI and async tasks with external triggers (webhooks, human approval, timeouts), you can build sophisticated human-in-the-loop AI systems.

### Can I use Active Agent with existing Rails apps?

Yes! Active Agent is designed to integrate seamlessly with existing Rails applications. It works alongside your existing models, controllers, and services.

### Can I self-host Active Agent?

Absolutely! The core framework is MIT licensed and can be self-hosted without limits on any tier. The hosted services (observability, evaluation, collaboration) and Pro gems are what differentiate the paid tiers.
