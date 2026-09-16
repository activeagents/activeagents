# frozen_string_literal: true

# Moved to the activeagent gem's dashboard engine, which this app mounts and
# configures (config/initializers/action_agent.rb). The name stays, in the
# acronym spelling the activeagent railtie's "MCP" inflection makes Zeitwerk
# expect of this file, so anything referring to it from outside keeps working.
MCPRecordingMiddleware = ActionAgent::MCPRecordingMiddleware
