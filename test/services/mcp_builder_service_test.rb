# frozen_string_literal: true

require "test_helper"

class McpBuilderServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
    @builder = McpBuilderService.new(agent: @agent)
  end

  test "build generates MCP server and returns config" do
    tools = [
      {
        name: "greet",
        description: "Greet a user by name",
        parameters: {
          type: "object",
          properties: { name: { type: "string" } },
          required: [ "name" ]
        }
      }
    ]

    config = @builder.build(name: "test_server", tools: tools)

    assert_equal "test_server", config[:name]
    assert_equal "node", config[:command]
    assert config[:storage_path].present?
    assert_includes config[:tools], "greet"
    assert File.exist?(config[:storage_path])
  end

  test "build creates valid JavaScript" do
    tools = [
      { name: "hello", description: "Say hello" }
    ]

    config = @builder.build(name: "hello_server", tools: tools)

    code = File.read(config[:storage_path])
    assert_includes code, "hello_server"
    assert_includes code, "1.0.0"
    assert_includes code, "@modelcontextprotocol/sdk"
    assert_includes code, "hello"
  end

  test "build with custom handler includes handler code" do
    tools = [
      {
        name: "add",
        description: "Add two numbers",
        handler: "const result = (args.a || 0) + (args.b || 0); return { content: [{ type: 'text', text: String(result) }] };"
      }
    ]

    config = @builder.build(name: "math_server", tools: tools)

    code = File.read(config[:storage_path])
    assert_includes code, "args.a"
    assert_includes code, "args.b"
  end

  test "build stores server in correct directory structure" do
    tools = [ { name: "test_tool", description: "Test" } ]

    config = @builder.build(name: "my_server", tools: tools)

    assert_includes config[:storage_path], @agent.id.to_s
    assert_includes config[:storage_path], "my-server"
    assert config[:storage_path].end_with?("server.mjs")
  end

  test "build extracts env vars from tools" do
    tools = [
      { name: "api_call", description: "Call API", env: { "API_KEY" => "required" } },
      { name: "db_query", description: "Query DB", env: { "DATABASE_URL" => "required" } }
    ]

    config = @builder.build(name: "env_server", tools: tools)

    assert_equal "required", config[:env]["API_KEY"]
    assert_equal "required", config[:env]["DATABASE_URL"]
  end

  test "validate returns errors for missing names" do
    tools = [ { description: "No name" } ]

    result = @builder.validate(tools: tools)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("missing name") }
  end

  test "validate returns errors for missing descriptions" do
    tools = [ { name: "test" } ]

    result = @builder.validate(tools: tools)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("missing description") }
  end

  test "validate returns errors for invalid tool names" do
    tools = [ { name: "InvalidName", description: "test" } ]

    result = @builder.validate(tools: tools)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("lowercase") }
  end

  test "validate passes for valid tools" do
    tools = [
      { name: "valid_tool", description: "A valid tool" },
      { name: "another_tool", description: "Another valid tool" }
    ]

    result = @builder.validate(tools: tools)
    assert result[:valid]
    assert_empty result[:errors]
  end

  test "build raises on invalid tools" do
    tools = [ { description: "missing name" } ]

    assert_raises(McpBuilderService::BuildError) do
      @builder.build(name: "bad", tools: tools)
    end
  end

  test "preview returns code without storing" do
    tools = [ { name: "test_tool", description: "Test" } ]

    code = @builder.preview(name: "preview_server", tools: tools)

    assert_includes code, "preview_server"
    assert_includes code, "test_tool"
    # Should not create a file
    path = Rails.root.join("tmp", "mcp_servers", @agent.id.to_s, "preview-server", "server.mjs")
    assert_not File.exist?(path)
  end

  test "build with multiple tools" do
    tools = [
      { name: "read_file", description: "Read a file" },
      { name: "write_file", description: "Write a file" },
      { name: "list_files", description: "List files" }
    ]

    config = @builder.build(name: "file_tools", tools: tools)

    assert_equal 3, config[:tools].size
    code = File.read(config[:storage_path])
    assert_includes code, "read_file"
    assert_includes code, "write_file"
    assert_includes code, "list_files"
  end

  teardown do
    # Clean up generated files
    dir = Rails.root.join("tmp", "mcp_servers", @agent.id.to_s)
    FileUtils.rm_rf(dir) if dir.exist?
  end
end
