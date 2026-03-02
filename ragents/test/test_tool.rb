# frozen_string_literal: true

require_relative "test_helper"

class TestTool < Minitest::Test
  def setup
    @tool = Ragents::Tool.new(
      name: "calculator",
      description: "Evaluates simple arithmetic",
      parameters: {
        type: "object",
        properties: {
          expression: { type: "string", description: "The arithmetic expression" }
        },
        required: ["expression"]
      }
    ) { |expression:| eval(expression).to_s }  # rubocop:disable Security/Eval
  end

  def test_tool_name
    assert_equal "calculator", @tool.name
  end

  def test_tool_description
    assert_equal "Evaluates simple arithmetic", @tool.description
  end

  def test_tool_is_frozen
    assert @tool.frozen?
  end

  def test_tool_execute_returns_string
    result = @tool.execute(expression: "2 + 2")
    assert_equal "4", result
  end

  def test_tool_execute_with_error_returns_error_hash_as_string
    bad_tool = Ragents::Tool.new(
      name: "broken",
      description: "Always fails",
      parameters: { type: "object", properties: {}, required: [] }
    ) { raise "Something went wrong" }

    result = bad_tool.execute
    assert_match "Something went wrong", result
  end

  def test_tool_to_schema
    schema = @tool.to_schema
    assert_equal "function",    schema[:type]
    assert_equal "calculator",  schema[:function][:name]
    assert_equal "Evaluates simple arithmetic", schema[:function][:description]
    assert_equal "object", schema[:function][:parameters][:type]
  end

  def test_tool_without_block_raises
    assert_raises(ArgumentError) do
      Ragents::Tool.new(name: "no_block", description: "d", parameters: {})
    end
  end

  def test_tool_parameters_are_frozen
    assert @tool.parameters.frozen?
  end
end

class TestToolRegistry < Minitest::Test
  def setup
    @registry = Ragents::ToolRegistry.new
  end

  def test_register_and_include
    tool = Ragents::Tool.new(name: "echo", description: "d") { |text:| text }
    @registry.register(tool)
    assert @registry.include?("echo")
  end

  def test_fetch_existing_tool
    tool = Ragents::Tool.new(name: "ping", description: "d") { "pong" }
    @registry.register(tool)
    assert_equal tool, @registry.fetch("ping")
  end

  def test_fetch_missing_tool_raises
    assert_raises(KeyError) { @registry.fetch("nonexistent") }
  end

  def test_execute_delegates_to_tool
    tool = Ragents::Tool.new(
      name: "greet",
      description: "d",
      parameters: { type: "object", properties: { name: { type: "string" } }, required: ["name"] }
    ) { |name:| "Hello, #{name}!" }
    @registry.register(tool)

    result = @registry.execute("greet", name: "Alice")
    assert_equal "Hello, Alice!", result
  end

  def test_schemas_returns_all_schemas
    t1 = Ragents::Tool.new(name: "t1", description: "d1") { "ok" }
    t2 = Ragents::Tool.new(name: "t2", description: "d2") { "ok" }
    @registry.register(t1).register(t2)

    schemas = @registry.schemas
    assert_equal 2, schemas.size
    names = schemas.map { |s| s[:function][:name] }
    assert_includes names, "t1"
    assert_includes names, "t2"
  end

  def test_registry_size
    @registry.register(Ragents::Tool.new(name: "a", description: "d") { "ok" })
    @registry.register(Ragents::Tool.new(name: "b", description: "d") { "ok" })
    assert_equal 2, @registry.size
  end

  def test_registry_rejects_non_tool
    assert_raises(TypeError) { @registry.register("not a tool") }
  end

  def test_new_registry_from_array
    tools = [
      Ragents::Tool.new(name: "x", description: "d") { "x" },
      Ragents::Tool.new(name: "y", description: "d") { "y" }
    ]
    registry = Ragents::ToolRegistry.new(tools)
    assert_equal 2, registry.size
    assert registry.include?("x")
    assert registry.include?("y")
  end
end
