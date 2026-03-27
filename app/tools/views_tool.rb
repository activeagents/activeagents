# frozen_string_literal: true

# ViewsTool - Template rendering for agents
#
# Enables agents to discover and render ERB templates, producing
# formatted output (HTML, text, JSON) from the application's view layer.
#
# Usage:
#   ViewsTool.call(operation: "list")
#   ViewsTool.call(operation: "render", template: "shared/_agent_card", locals: { agent: { name: "Test" } })
#
class ViewsTool < BaseTool
  tool_name "views"
  description "Discover and render application templates. Use this to produce formatted HTML, email, or text output from existing templates."

  parameter :operation, type: "string", description: "The operation to perform", required: true, enum: %w[list render]
  parameter :template, type: "string", description: "Template path to render (e.g. 'shared/_card'). Required for render."
  parameter :locals, type: "object", description: "Local variables to pass to the template"
  parameter :layout, type: "string", description: "Layout to wrap the rendered template"
  parameter :format, type: "string", description: "Render format", enum: %w[html text json], default: "html"

  # Templates agents are allowed to render
  ALLOWED_TEMPLATE_DIRS = %w[
    shared
    agents
    components
  ].freeze

  def call(operation:, template: nil, locals: {}, layout: nil, format: "html")
    case operation
    when "list"
      list_templates
    when "render"
      raise ParameterError, "template is required for render operation" if template.blank?
      render_template(template, locals, layout, format)
    else
      raise ParameterError, "Unknown operation: #{operation}. Must be one of: list, render"
    end
  end

  private

  def list_templates
    templates = []

    view_paths = ActionController::Base.view_paths.map(&:to_s)
    view_paths.each do |view_path|
      ALLOWED_TEMPLATE_DIRS.each do |dir|
        dir_path = File.join(view_path, dir)
        next unless File.directory?(dir_path)

        Dir.glob(File.join(dir_path, "**", "*.erb")).each do |file|
          relative = file.delete_prefix("#{view_path}/")
          templates << {
            path: relative,
            name: File.basename(relative, ".*"),
            directory: File.dirname(relative),
            partial: File.basename(relative).start_with?("_")
          }
        end
      end
    end

    { templates: templates, count: templates.size }
  end

  def render_template(template, locals, layout, format)
    validate_template_path!(template)

    # Symbolize local variable keys
    symbolized_locals = locals.deep_symbolize_keys

    rendered = ApplicationController.render(
      template: template,
      locals: symbolized_locals,
      layout: layout,
      formats: [format.to_sym]
    )

    {
      template: template,
      content: rendered,
      format: format,
      rendered_at: Time.current.iso8601
    }
  rescue ActionView::MissingTemplate => e
    raise ExecutionError, "Template not found: #{template}"
  rescue => e
    raise ExecutionError, "Failed to render template #{template}: #{e.message}"
  end

  def validate_template_path!(template)
    # Prevent directory traversal
    if template.include?("..") || template.start_with?("/")
      raise ParameterError, "Invalid template path: #{template}"
    end

    # Ensure template is in an allowed directory
    dir = template.split("/").first
    unless ALLOWED_TEMPLATE_DIRS.include?(dir)
      raise ParameterError, "Templates from '#{dir}' directory are not accessible. Allowed directories: #{ALLOWED_TEMPLATE_DIRS.join(', ')}"
    end
  end
end
