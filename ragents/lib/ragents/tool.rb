# frozen_string_literal: true

module Ragents
  # Tool represents a capability that can be invoked by the LLM during an
  # agent run.  Tools are defined as plain Ruby objects with a callable
  # #execute method, plus a JSON Schema descriptor that the LLM sees.
  #
  # ## Ractor Safety
  #
  # Tool definitions (name, description, schema) are frozen at creation time
  # and can therefore be shared across Ractors without copying.
  #
  # Tool *execution* happens inside the Ractor that owns the conversation
  # context.  The result (a String or Hash) is then wrapped in a
  # ToolResultMessage and passed back into the context.
  #
  # ## Usage
  #
  #   weather_tool = Ragents::Tool.new(
  #     name: "get_weather",
  #     description: "Get the current weather for a location",
  #     parameters: {
  #       type: "object",
  #       properties: {
  #         location: { type: "string", description: "City name" }
  #       },
  #       required: ["location"]
  #     }
  #   ) do |location:|
  #     WeatherService.fetch(location)
  #   end
  #
  #   result = weather_tool.execute(location: "London")

  class Tool
    attr_reader :name, :description, :parameters

    def initialize(name:, description:, parameters: {}, &block)
      @name = name.to_s.freeze
      @description = description.to_s.freeze
      @parameters = deep_freeze(parameters)
      @callable = block

      raise ArgumentError, "Tool #{@name} requires a block or override of #call" unless @callable || respond_to?(:call)

      freeze
    end

    # Execute the tool with the given keyword arguments.
    # Returns a String or Hash that will be serialised into a ToolResultMessage.
    def execute(**kwargs)
      result = if @callable
                 @callable.call(**kwargs)
      else
                 call(**kwargs)
      end

      normalise_result(result)
    rescue StandardError => e
      { error: e.message }
    end

    # JSON Schema representation consumed by LLM providers.
    def to_schema
      {
        type: "function",
        function: {
          name: @name,
          description: @description,
          parameters: @parameters
        }
      }
    end

    def to_s   = @name
    def inspect = "#<Ragents::Tool name=#{@name}>"

    private

    def normalise_result(result)
      case result
      when String then result
      when Hash, Array then JSON.generate(result)
      when nil then ""
      else result.to_s
      end
    end

    def deep_freeze(obj)
      case obj
      when Hash  then obj.transform_keys(&:to_sym).transform_values { |v| deep_freeze(v) }.freeze
      when Array then obj.map { |v| deep_freeze(v) }.freeze
      when String then obj.dup.freeze
      else obj
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ToolRegistry — thread/Ractor-safe registry of named Tool objects.
  #
  # The registry itself is NOT shared across Ractors.  Instead, agents receive
  # their set of tools at creation time (as an Array of frozen Tool objects)
  # and build a local registry inside their own Ractor.
  # ---------------------------------------------------------------------------
  class ToolRegistry
    def initialize(tools = [])
      @tools = {}
      tools.each { |t| register(t) }
    end

    def register(tool)
      raise TypeError, "Expected Ragents::Tool, got #{tool.class}" unless tool.is_a?(Tool)

      @tools[tool.name] = tool
      self
    end

    def fetch(name)
      @tools.fetch(name.to_s) { raise KeyError, "Unknown tool: #{name}" }
    end

    def include?(name) = @tools.key?(name.to_s)

    def schemas = @tools.values.map(&:to_schema)

    def execute(name, **kwargs)
      fetch(name).execute(**kwargs)
    end

    def names = @tools.keys
    def size  = @tools.size
    def empty? = @tools.empty?

    def to_a = @tools.values
  end
end
