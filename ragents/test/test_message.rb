# frozen_string_literal: true

require_relative "test_helper"

class TestMessage < Minitest::Test
  # ---------------------------------------------------------------------------
  # UserMessage
  # ---------------------------------------------------------------------------

  def test_user_message_has_correct_role
    msg = Ragents::UserMessage.new(content: "Hello")
    assert_equal :user, msg.role
  end

  def test_user_message_freezes_content
    msg = Ragents::UserMessage.new(content: "Hello")
    assert msg.content.frozen?
  end

  def test_user_message_optional_name
    msg = Ragents::UserMessage.new(content: "Hi", name: "Alice")
    assert_equal "Alice", msg.name
  end

  def test_user_message_nil_name_by_default
    msg = Ragents::UserMessage.new(content: "Hi")
    assert_nil msg.name
  end

  def test_user_message_is_frozen_data_struct
    msg = Ragents::UserMessage.new(content: "Hi")
    assert msg.frozen?
  end

  # ---------------------------------------------------------------------------
  # AssistantMessage
  # ---------------------------------------------------------------------------

  def test_assistant_message_role
    msg = Ragents::AssistantMessage.new(content: "I can help.")
    assert_equal :assistant, msg.role
  end

  def test_assistant_message_stores_token_counts
    msg = Ragents::AssistantMessage.new(content: "Hi", input_tokens: 10, output_tokens: 5)
    assert_equal 10, msg.input_tokens
    assert_equal 5,  msg.output_tokens
  end

  def test_assistant_message_stores_model
    msg = Ragents::AssistantMessage.new(content: "Hi", model: "gpt-4o")
    assert_equal "gpt-4o", msg.model
  end

  # ---------------------------------------------------------------------------
  # SystemMessage
  # ---------------------------------------------------------------------------

  def test_system_message_role
    msg = Ragents::SystemMessage.new(content: "You are helpful.")
    assert_equal :system, msg.role
  end

  # ---------------------------------------------------------------------------
  # ToolCallMessage
  # ---------------------------------------------------------------------------

  def test_tool_call_message_structure
    msg = Ragents::ToolCallMessage.new(
      tool_call_id: "call_123",
      name: "search",
      arguments: { query: "Ruby Ractors" }
    )
    assert_equal "call_123", msg.tool_call_id
    assert_equal "search",   msg.name
    assert_equal({ query: "Ruby Ractors" }, msg.arguments)
  end

  def test_tool_call_message_freezes_arguments
    msg = Ragents::ToolCallMessage.new(tool_call_id: "1", name: "t", arguments: { x: "y" })
    assert msg.arguments.frozen?
  end

  def test_tool_call_message_role
    msg = Ragents::ToolCallMessage.new(tool_call_id: "1", name: "t")
    assert_equal :assistant, msg.role
  end

  # ---------------------------------------------------------------------------
  # ToolResultMessage
  # ---------------------------------------------------------------------------

  def test_tool_result_success
    msg = Ragents::ToolResultMessage.new(tool_call_id: "1", name: "search", content: "Found it")
    assert msg.success?
    assert_equal "Found it", msg.content
    assert_nil msg.error
  end

  def test_tool_result_error
    msg = Ragents::ToolResultMessage.new(tool_call_id: "1", name: "search", error: "Not found")
    refute msg.success?
    assert_equal "Not found", msg.error
  end

  def test_tool_result_role
    msg = Ragents::ToolResultMessage.new(tool_call_id: "1", name: "t", content: "ok")
    assert_equal :tool, msg.role
  end

  # ---------------------------------------------------------------------------
  # AgentCallMessage / AgentResultMessage
  # ---------------------------------------------------------------------------

  def test_agent_call_message
    msg = Ragents::AgentCallMessage.new(
      call_id: "ac_1",
      agent_name: "researcher",
      input: "Explain Ractors"
    )
    assert_equal "ac_1",       msg.call_id
    assert_equal "researcher", msg.agent_name
    assert_equal "Explain Ractors", msg.input
  end

  def test_agent_result_success
    msg = Ragents::AgentResultMessage.new(call_id: "1", agent_name: "r", output: "result")
    assert msg.success?
  end

  def test_agent_result_error
    msg = Ragents::AgentResultMessage.new(call_id: "1", agent_name: "r", error: "failed")
    refute msg.success?
  end

  # ---------------------------------------------------------------------------
  # ErrorMessage
  # ---------------------------------------------------------------------------

  def test_error_message_from_exception
    begin
      raise RuntimeError, "something went wrong"
    rescue => e
      msg = Ragents::ErrorMessage.from_exception(source: "test", exception: e)
      assert_equal "RuntimeError",          msg.exception_class
      assert_equal "something went wrong",  msg.message
      assert_equal "test",                  msg.source
      assert_kind_of Array,                 msg.backtrace
    end
  end

  def test_error_message_frozen_fields
    begin
      raise "oops"
    rescue => e
      msg = Ragents::ErrorMessage.from_exception(source: "s", exception: e)
      assert msg.exception_class.frozen?
      assert msg.message.frozen?
      assert msg.backtrace.frozen?
    end
  end
end
