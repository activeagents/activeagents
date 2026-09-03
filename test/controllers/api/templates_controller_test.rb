# frozen_string_literal: true

require "test_helper"

class Api::TemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)

    @public_template = create_template(
      name: "Public Helper",
      slug: "public-helper-#{SecureRandom.hex(4)}",
      public: true
    )

    @private_template = create_template(
      name: "Unpublished Draft",
      slug: "unpublished-draft-#{SecureRandom.hex(4)}",
      public: false,
      instructions: "SECRET SYSTEM PROMPT",
      instruction_sets: %w[secret-playbook],
      model_config: { "temperature" => 0.1, "secret_knob" => true }
    )
  end

  # ===========================================
  # Anonymous access
  # ===========================================

  # The bug: `allow_unauthenticated_access only: [:index, :show]` plus a bare
  # `AgentTemplate.find` in #show served instructions/instruction_sets/
  # model_config for `public: false` templates to anyone walking the id space.
  test "show does not serve a non-public template to an anonymous client" do
    get "/api/templates/#{@private_template.id}"

    assert_redirected_to "/session/new"
    refute_includes response.body, "SECRET SYSTEM PROMPT"
    refute_includes response.body, "secret-playbook"
  end

  test "show does not serve any template to an anonymous client" do
    get "/api/templates/#{@public_template.id}"

    assert_redirected_to "/session/new"
  end

  test "index requires a session" do
    get "/api/templates"

    assert_redirected_to "/session/new"
  end

  # ===========================================
  # Authenticated dashboard path
  # ===========================================

  test "show returns full template details for a signed-in user" do
    sign_in_as(@user)

    get "/api/templates/#{@public_template.id}"

    assert_response :success
    template = json_response["template"]
    assert_equal @public_template.id, template["id"]
    assert_equal "You are a helpful assistant.", template["instructions"]
    assert_equal [ "rails" ], template["instruction_sets"]
    assert_equal({ "temperature" => 0.4 }, template["model_config"])
  end

  test "index returns the public library for a signed-in user" do
    sign_in_as(@user)

    get "/api/templates"

    assert_response :success
    ids = json_response["templates"].map { |t| t["id"] }
    assert_includes ids, @public_template.id
    refute_includes ids, @private_template.id
    assert_equal AgentTemplate::CATEGORIES, json_response["categories"]
  end

  test "use still creates an agent for a signed-in user" do
    sign_in_as(@user)

    assert_difference -> { @user.agents.count }, 1 do
      post "/api/templates/#{@public_template.id}/use", params: { name: "My Copy" }
    end

    assert_response :created
    assert_equal "My Copy", json_response["agent"]["name"]
  end

  # The dashboard opens the new agent in the editor straight from this
  # response. A summary (no instructions/tools/model_config) seeded the editor
  # with empty fields, and its first Save persisted those over the template's
  # real configuration (#113).
  test "use returns the full agent detail the editor initializes from" do
    sign_in_as(@user)
    template = create_template(
      name: "Configured",
      slug: "configured-#{SecureRandom.hex(4)}",
      tools: %w[terminal code],
      mcp_servers: [ { "name" => "playwright", "command" => "npx" } ],
      model_config: { "temperature" => 0.2, "max_tokens" => 4096 }
    )

    post "/api/templates/#{template.id}/use", params: { name: "From Template" }

    assert_response :created
    agent = json_response["agent"]
    assert_equal "You are a helpful assistant.", agent["instructions"]
    assert_equal %w[terminal code], agent["tools"]
    assert_equal [ "rails" ], agent["instruction_sets"]
    assert_equal [ { "name" => "playwright", "command" => "npx" } ], agent["mcp_servers"]
    assert_equal({ "temperature" => 0.2, "max_tokens" => 4096 }, agent["model_config"])
    assert agent.key?("action_prompts"), "detail shape must carry action_prompts"
    assert agent.key?("response_format"), "detail shape must carry response_format"
  end

  private

  def create_template(**attrs)
    defaults = {
      name: "Test Template",
      slug: "test-template-#{SecureRandom.hex(4)}",
      description: "A test template",
      category: "development",
      provider: "openai",
      model: "gpt-4o-mini",
      preset_type: "terminal",
      instructions: "You are a helpful assistant.",
      instruction_sets: %w[rails],
      model_config: { "temperature" => 0.4 }
    }
    AgentTemplate.create!(defaults.merge(attrs))
  end
end
