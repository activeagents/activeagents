# frozen_string_literal: true

require "test_helper"

class AgentMemoryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user, name: "Memory Bot")
  end

  test "for finds or creates one memory per subject and scope" do
    memory = AgentMemory.for(@agent)

    assert_equal memory, AgentMemory.for(@agent)
    assert_not_equal memory, AgentMemory.for(@agent, scope: "research")
    assert_equal "default", memory.scope
  end

  test "remember appends entries and recall returns newest first" do
    memory = AgentMemory.for(@agent)
    memory.remember("first note", source_agent: "MemoryBotAgent")
    memory.remember("second note", source_agent: "MemoryBotAgent", category: "task")

    entries = memory.recall
    assert_equal [ "second note", "first note" ], entries.map(&:content)

    assert_equal [ "second note" ], memory.recall(category: "task").map(&:content)
    assert_equal [ "second note" ], memory.recall(limit: 1).map(&:content)
  end

  test "memory is shared across agents on the same subject for handoff" do
    writer = AgentMemory.for(@agent)
    writer.remember("Research complete: use approach B", source_agent: "ResearchAgent", category: "handoff")

    reader = AgentMemory.for(@agent)
    handoff = reader.recall(category: "handoff")
    assert_equal 1, handoff.size
    assert_equal "ResearchAgent", handoff.first.source_agent
  end

  test "to_prompt formats the summary list with provenance" do
    memory = AgentMemory.for(@agent)
    assert_equal "", memory.to_prompt

    memory.remember("User prefers terse answers", source_agent: "SupportAgent")
    prompt = memory.to_prompt
    assert_includes prompt, "Memory notes for this subject:"
    assert_includes prompt, "- User prefers terse answers (SupportAgent)"
  end

  test "destroying the agent destroys its memories" do
    memory = AgentMemory.for(@agent)
    memory.remember("note")

    @agent.destroy!
    assert_not AgentMemory.exists?(memory.id)
  end
end
