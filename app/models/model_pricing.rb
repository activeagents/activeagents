# frozen_string_literal: true

# Token-count -> estimated USD. The implementation lives in solid_agent
# (RubyLLM registry rates when available, static pattern-table fallback,
# mock models free); this constant keeps the app-local name that the
# metrics/evaluation code and specs use.
ModelPricing = SolidAgent::ModelPricing
