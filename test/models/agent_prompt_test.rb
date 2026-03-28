# frozen_string_literal: true

require "test_helper"

class AgentPromptTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  test "belongs to agent" do
    prompt = @agent.agent_prompts.create!(name: "greeting", content: "Hello {name}")
    assert_equal @agent, prompt.agent
  end

  test "validates name presence" do
    prompt = @agent.agent_prompts.build(name: nil, content: "test")
    assert_not prompt.valid?
  end

  test "validates content presence" do
    prompt = @agent.agent_prompts.build(name: "test", content: nil)
    assert_not prompt.valid?
  end

  test "name is unique per agent and version" do
    @agent.agent_prompts.create!(name: "greeting", content: "v1", version: 1)
    duplicate = @agent.agent_prompts.build(name: "greeting", content: "v1 copy", version: 1)
    assert_not duplicate.valid?
  end

  test "same name with different version is allowed" do
    @agent.agent_prompts.create!(name: "greeting", content: "v1", version: 1)
    v2 = @agent.agent_prompts.build(name: "greeting", content: "v2", version: 2)
    assert v2.valid?
  end

  test "computes content hash on save" do
    prompt = @agent.agent_prompts.create!(name: "test", content: "Hello world")
    assert_equal Digest::SHA256.hexdigest("Hello world"), prompt.content_hash
  end

  test "render substitutes variables" do
    prompt = @agent.agent_prompts.create!(name: "greeting", content: "Hello {name}, welcome to {place}")
    result = prompt.render(name: "Alice", place: "Wonderland")
    assert_equal "Hello Alice, welcome to Wonderland", result
  end

  test "render leaves unmatched placeholders" do
    prompt = @agent.agent_prompts.create!(name: "test", content: "Hello {name}, {unknown}")
    result = prompt.render(name: "Alice")
    assert_equal "Hello Alice, {unknown}", result
  end

  test "create_new_version increments version" do
    prompt = @agent.agent_prompts.create!(name: "greeting", content: "v1")
    v2 = prompt.create_new_version("v2 content")

    assert_equal 2, v2.version
    assert_equal "v2 content", v2.content
    assert_equal "greeting", v2.name
  end

  test "next_version returns correct number" do
    prompt = @agent.agent_prompts.create!(name: "test", content: "v1", version: 1)
    assert_equal 2, prompt.next_version

    prompt.create_new_version("v2")
    assert_equal 3, prompt.next_version
  end
end
