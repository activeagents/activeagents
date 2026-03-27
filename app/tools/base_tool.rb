# frozen_string_literal: true

# BaseTool - Abstract base class for all agent tools
#
# Tools are callable units that agents can invoke during execution.
# Each tool defines its name, description, parameter schema, and
# execution logic. The parameter schema follows the JSON Schema
# format used by LLM function/tool calling APIs.
#
# Example subclass:
#   class MyTool < BaseTool
#     tool_name "my_tool"
#     description "Does something useful"
#     parameter :input, type: "string", description: "The input value", required: true
#
#     def call(input:)
#       "Processed: #{input}"
#     end
#   end
#
class BaseTool
  class ToolError < StandardError; end
  class ParameterError < ToolError; end
  class ExecutionError < ToolError; end

  class_attribute :_tool_name
  class_attribute :_description
  class_attribute :_parameters, default: {}
  class_attribute :_required_params, default: []

  class << self
    def tool_name(name = nil)
      if name
        self._tool_name = name.to_s
      else
        _tool_name || self.name.demodulize.underscore.delete_suffix("_tool")
      end
    end

    def description(desc = nil)
      if desc
        self._description = desc
      else
        _description
      end
    end

    def parameter(name, type:, description:, required: false, enum: nil, items: nil, default: nil)
      self._parameters = _parameters.merge(
        name.to_s => { type: type, description: description, enum: enum, items: items, default: default }.compact
      )
      self._required_params = (_required_params + [name.to_s]) if required
    end

    # Returns the tool definition in the format expected by LLM function calling APIs
    def to_tool_definition
      {
        name: tool_name,
        description: _description,
        parameters: {
          type: "object",
          properties: _parameters,
          required: _required_params
        }
      }
    end

    # Convenience method to instantiate and call
    def call(**params)
      new.call(**params)
    end
  end

  def call(**params)
    raise NotImplementedError, "#{self.class.name} must implement #call"
  end

  # Validate parameters against the schema
  def validate_params!(params)
    self.class._required_params.each do |name|
      unless params.key?(name.to_sym) || params.key?(name.to_s)
        raise ParameterError, "Missing required parameter: #{name}"
      end
    end

    params.each_key do |key|
      unless self.class._parameters.key?(key.to_s)
        raise ParameterError, "Unknown parameter: #{key}"
      end
    end
  end
end
