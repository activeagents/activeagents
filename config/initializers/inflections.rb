# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# Acronyms for Zeitwerk autoloading
# This ensures class names like MCPRecordingMiddleware and UIGeneratorAgent
# are correctly matched to their file names (mcp_recording_middleware.rb, ui_generator_agent.rb)
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    "mcp_recording_middleware" => "MCPRecordingMiddleware",
    "ui_generator_agent" => "UIGeneratorAgent"
  )
end
