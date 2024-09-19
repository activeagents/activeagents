# frozen_string_literal: true

require 'action_view'

module ActiveAgent
  module ActionPrompt
    extend ActiveSupport::Concern

    included do
      include ActionView::Rendering
      include Rails.application.routes.url_helpers
      self.view_paths = ["app/views"]
    end

    def render_instructions(action_name = :instructions)
      render_template(action_name, :text)
    end

    def render_action(action_name, format: :html)
      render_template(action_name, format)
    end

    def render_view(view_name, format: :html)
      render_template(view_name, format)
    end

    private

    def render_template(action_name, format)
      lookup_context.formats = [format]
      template = "#{self.class.name.underscore}/#{action_name}"
      assigns = instance_variables.each_with_object({}) do |var, hash|
        hash[var.to_s.delete("@").to_sym] = instance_variable_get(var)
      end
      render template: template, locals: assigns
    end
  end
end
