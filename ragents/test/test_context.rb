# frozen_string_literal: true

require_relative "test_helper"

class TestContext < Minitest::Test
  def setup
    @context = Ragents::Context.new(agent_id: "test_agent")
  end

  def test_new_context_is_empty
    assert @context.empty?
    assert_equal 0, @context.size
  end

  def test_add_user_message
    @context.add(Ragents::UserMessage.new(content: "Hello"))
    assert_equal 1, @context.size
  end

  def test_add_returns_self_for_chaining
    result = @context.add(Ragents::UserMessage.new(content: "Hi"))
    assert_equal @context, result
  end

  def test_shovel_operator_is_alias_for_add
    @context << Ragents::UserMessage.new(content: "Hi")
    assert_equal 1, @context.size
  end

  def test_messages_returns_copy
    @context.add(Ragents::UserMessage.new(content: "Hi"))
    msgs = @context.messages
    msgs << "intruder"
    assert_equal 1, @context.size, "Internal array should not be modified"
  end

  def test_system_messages_filter
    @context.add(Ragents::SystemMessage.new(content: "Instructions"))
    @context.add(Ragents::UserMessage.new(content: "Hi"))
    assert_equal 1, @context.system_messages.size
    assert_equal 1, @context.user_messages.size
  end

  def test_to_api_messages_formats_correctly
    @context.add(Ragents::SystemMessage.new(content: "Be helpful"))
    @context.add(Ragents::UserMessage.new(content: "Hello"))
    @context.add(Ragents::AssistantMessage.new(content: "Hi there!"))

    api = @context.to_api_messages
    assert_equal 3, api.size
    assert_equal "system",    api[0][:role]
    assert_equal "user",      api[1][:role]
    assert_equal "assistant", api[2][:role]
    assert_equal "Be helpful", api[0][:content]
  end

  def test_to_api_messages_formats_tool_call
    @context.add(Ragents::UserMessage.new(content: "Search for Ruby"))
    @context.add(Ragents::ToolCallMessage.new(
      tool_call_id: "call_1",
      name: "search",
      arguments: { query: "Ruby" }
    ))
    @context.add(Ragents::ToolResultMessage.new(
      tool_call_id: "call_1",
      name: "search",
      content: "Ruby is great!"
    ))

    api = @context.to_api_messages
    assert_equal 3, api.size

    tool_call = api[1]
    assert_equal "assistant", tool_call[:role]
    assert tool_call[:tool_calls].is_a?(Array)
    assert_equal "search", tool_call[:tool_calls][0][:function][:name]

    tool_result = api[2]
    assert_equal "tool", tool_result[:role]
    assert_equal "call_1", tool_result[:tool_call_id]
    assert_equal "Ruby is great!", tool_result[:content]
  end

  def test_snapshot_returns_frozen_array_of_frozen_messages
    @context.add(Ragents::UserMessage.new(content: "Hi"))
    @context.add(Ragents::AssistantMessage.new(content: "Hello"))

    snap = @context.snapshot
    assert snap.frozen?
    snap.each { |m| assert m.frozen?, "Message #{m.class} should be frozen" }
  end

  def test_import_rebuilds_context
    @context.add(Ragents::SystemMessage.new(content: "Instructions"))
    @context.add(Ragents::UserMessage.new(content: "Question"))
    @context.add(Ragents::AssistantMessage.new(content: "Answer"))

    snap   = @context.snapshot
    child  = Ragents::Context.import(snap, agent_id: "child_agent")

    assert_equal 3, child.size
    assert_equal "Question", child.user_messages.first.content
    assert_equal "Answer",   child.assistant_messages.first.content
  end

  def test_import_creates_independent_context
    @context.add(Ragents::UserMessage.new(content: "Original"))
    snap  = @context.snapshot
    child = Ragents::Context.import(snap, agent_id: "child")

    child.add(Ragents::UserMessage.new(content: "Child addition"))
    assert_equal 1, @context.size, "Parent context should not be affected"
    assert_equal 2, child.size
  end

  def test_reset_conversation_keeps_system_messages
    @context.add(Ragents::SystemMessage.new(content: "You are helpful"))
    @context.add(Ragents::UserMessage.new(content: "Hello"))
    @context.add(Ragents::AssistantMessage.new(content: "Hi"))

    @context.reset_conversation!

    assert_equal 1, @context.size
    assert_equal 1, @context.system_messages.size
    assert_equal 0, @context.user_messages.size
  end

  def test_tail_returns_last_n_messages
    5.times { |i| @context.add(Ragents::UserMessage.new(content: "Msg #{i}")) }
    last_three = @context.tail(3)
    assert_equal 3, last_three.size
    assert_equal "Msg 4", last_three.last.content
  end

  def test_context_has_unique_id
    c1 = Ragents::Context.new(agent_id: "a")
    c2 = Ragents::Context.new(agent_id: "a")
    refute_equal c1.id, c2.id
  end
end
