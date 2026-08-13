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
# This ensures class names like UIGeneratorAgent are correctly matched to
# their file names (ui_generator_agent.rb).
#
# These apply to every autoloader, the dashboard engine's included, so keep
# them to names this app actually owns — an entry here for a file the engine
# ships would make the gem unloadable in any app without the same entry.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    "ui_generator_agent" => "UIGeneratorAgent"
  )
end
