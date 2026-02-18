# frozen_string_literal: true

require "test_helper"

class AgentVersionTest < ActiveSupport::TestCase
  # ===========================================
  # Association Tests
  # ===========================================

  test "belongs to agent" do
    user = create_user
    agent = create_agent(user: user)
    version = agent.latest_version

    assert_equal agent, version.agent
  end

  # ===========================================
  # Validation Tests
  # ===========================================

  test "requires version_number" do
    user = create_user
    agent = create_agent(user: user)

    version = agent.agent_versions.build(
      version_number: nil,
      configuration_snapshot: { name: "test" }
    )

    assert_not version.valid?
    # version_number validation - either blank or uniqueness error
    assert version.errors[:version_number].any?
  end

  test "requires configuration_snapshot" do
    user = create_user
    agent = create_agent(user: user)

    version = agent.agent_versions.build(version_number: 2)

    assert_not version.valid?
    assert_includes version.errors[:configuration_snapshot], "can't be blank"
  end

  test "version_number must be unique per agent" do
    user = create_user
    agent = create_agent(user: user)

    # Version 1 is created on agent creation
    duplicate = agent.agent_versions.build(
      version_number: 1,
      configuration_snapshot: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version_number], "has already been taken"
  end

  test "same version_number can exist for different agents" do
    user = create_user
    agent1 = create_agent(user: user, name: "Agent 1")
    agent2 = create_agent(user: user, name: "Agent 2")

    # Both agents have version 1
    assert_equal 1, agent1.latest_version.version_number
    assert_equal 1, agent2.latest_version.version_number
  end

  # ===========================================
  # Configuration Snapshot Tests
  # ===========================================

  test "configuration_snapshot stores all config fields" do
    user = create_user
    agent = create_agent(
      user: user,
      instructions: "Test instructions",
      tools: ["terminal", "code"],
      model_config: { temperature: 0.5 }
    )

    snapshot = agent.latest_version.configuration_snapshot

    assert_equal "Test instructions", snapshot["instructions"]
    assert_equal ["terminal", "code"], snapshot["tools"]
    assert_equal({ "temperature" => 0.5 }, snapshot["model_config"])
  end

  test "snapshot captures state at version creation time" do
    user = create_user
    agent = create_agent(user: user, instructions: "Original")

    original_version = agent.latest_version
    assert_equal "Original", original_version.configuration_snapshot["instructions"]

    agent.update!(instructions: "Updated")

    # Original version still has old instructions
    original_version.reload
    assert_equal "Original", original_version.configuration_snapshot["instructions"]

    # New version has updated instructions
    assert_equal "Updated", agent.latest_version.configuration_snapshot["instructions"]
  end

  # ===========================================
  # Version Navigation Tests
  # ===========================================

  test "previous returns prior version" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    version1 = agent.latest_version

    agent.update!(instructions: "V2")
    version2 = agent.latest_version

    assert_equal version1, version2.previous
    assert_nil version1.previous
  end

  test "next_version returns following version" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    version1 = agent.latest_version

    agent.update!(instructions: "V2")
    version2 = agent.latest_version

    assert_equal version2, version1.next_version
    assert_nil version2.next_version
  end

  test "latest? returns true only for most recent version" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    version1 = agent.latest_version

    assert version1.latest?

    agent.update!(instructions: "V2")
    version1.reload

    assert_not version1.latest?
    assert agent.latest_version.latest?
  end

  test "initial? returns true only for version 1" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    version1 = agent.latest_version

    assert version1.initial?

    agent.update!(instructions: "V2")
    version2 = agent.latest_version

    assert version1.initial?
    assert_not version2.initial?
  end

  # ===========================================
  # Diff Tests
  # ===========================================

  test "diff returns changed fields between versions" do
    user = create_user
    agent = create_agent(user: user, instructions: "Original", tools: ["terminal"])
    version1 = agent.latest_version

    agent.update!(instructions: "Updated", tools: ["terminal", "code"])
    version2 = agent.latest_version

    diff = version2.diff(version1)

    assert diff.key?("instructions")
    assert_equal "Original", diff["instructions"][:from]
    assert_equal "Updated", diff["instructions"][:to]

    assert diff.key?("tools")
    assert_equal ["terminal"], diff["tools"][:from]
    assert_equal ["terminal", "code"], diff["tools"][:to]
  end

  test "diff returns empty hash for identical versions" do
    user = create_user
    agent = create_agent(user: user)
    version = agent.latest_version

    diff = version.diff(version)

    assert_empty diff
  end

  test "diff returns empty hash when compared to nil" do
    user = create_user
    agent = create_agent(user: user)
    version = agent.latest_version

    diff = version.diff(nil)

    assert_empty diff
  end

  # ===========================================
  # Scope Tests
  # ===========================================

  test "recent scope orders by version_number desc" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    agent.update!(instructions: "V2")
    agent.update!(instructions: "V3")

    versions = agent.agent_versions.recent

    assert_equal 3, versions.first.version_number
    assert_equal 1, versions.last.version_number
  end

  test "by_version scope finds specific version" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1")
    agent.update!(instructions: "V2")
    agent.update!(instructions: "V3")

    version = agent.agent_versions.by_version(2).first

    assert_equal 2, version.version_number
    assert_equal "V2", version.configuration_snapshot["instructions"]
  end

  # ===========================================
  # Change Summary Tests
  # ===========================================

  test "initial version has creation summary" do
    user = create_user
    agent = create_agent(user: user)

    assert_equal "Initial creation", agent.latest_version.change_summary
  end

  test "subsequent versions have changed fields in summary" do
    user = create_user
    agent = create_agent(user: user, instructions: "V1", tools: [])

    agent.update!(instructions: "V2")

    assert_includes agent.latest_version.change_summary, "instructions"
  end
end
