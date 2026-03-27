# frozen_string_literal: true

require "test_helper"

class Api::ToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "GET /api/tools returns all tools" do
    get "/api/tools"

    assert_response :success
    data = json_response
    assert_equal 6, data["total"]
    assert_equal 6, data["tools"].size

    tool_names = data["tools"].map { |t| t["name"] }
    assert_includes tool_names, "fetch"
    assert_includes tool_names, "filesystem"
    assert_includes tool_names, "bash"
    assert_includes tool_names, "agents"
    assert_includes tool_names, "views"
    assert_includes tool_names, "prompts"
  end

  test "GET /api/tools returns tool metadata with descriptions" do
    get "/api/tools"

    assert_response :success
    data = json_response
    data["tools"].each do |tool|
      assert tool["name"].present?, "Tool name should be present"
      assert tool["display_name"].present?, "Display name should be present"
      assert tool["description"].present?, "Description should be present"
      assert tool["parameters"].present?, "Parameters should be present"
    end
  end

  test "GET /api/tools/:id returns specific tool definition" do
    get "/api/tools/fetch"

    assert_response :success
    data = json_response
    assert_equal "fetch", data["tool"]["name"]
    assert data["tool"]["description"].present?
    assert data["tool"]["parameters"].present?
  end

  test "GET /api/tools/:id returns 404 for unknown tool" do
    get "/api/tools/nonexistent"

    assert_response :not_found
    assert_includes json_response["error"], "not found"
  end

  test "POST /api/tools/:id/test executes a tool" do
    post "/api/tools/prompts/test", params: {
      params: {
        operation: "build",
        template: "Hello {name}",
        variables: { name: "World" }
      }
    }, as: :json

    assert_response :success
    data = json_response
    assert data["success"]
    assert_equal "prompts", data["tool"]
    assert_equal "Hello World", data["result"]["prompt"]
  end

  test "POST /api/tools/:id/test returns error for invalid params" do
    post "/api/tools/prompts/test", params: {
      params: { operation: "build" }
    }, as: :json

    assert_response :unprocessable_entity
    data = json_response
    assert_not data["success"]
    assert data["error"].present?
  end

  test "POST /api/tools/:id/test returns 404 for unknown tool" do
    post "/api/tools/nonexistent/test", params: { params: {} }, as: :json

    assert_response :not_found
  end
end
