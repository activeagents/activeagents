# frozen_string_literal: true

require "test_helper"

class AdminAgentScaffoldTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @resource = AdminResource.register_report!(
      account: @account,
      service_name: "support_inbox",
      environment: "production",
      payload: {
        "name" => "Ticket",
        "table_name" => "tickets",
        "columns" => [
          { "name" => "subject", "type" => "string", "null" => false },
          { "name" => "status", "type" => "string", "null" => false, "default" => "open" }
        ],
        "associations" => [
          { "kind" => "has_many", "name" => "replies", "class_name" => "Reply" }
        ],
        "record_count" => 1042
      }
    )
  end

  test "scaffolds an active admin agent from the resource manifest" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    assert agent.persisted?
    assert_equal @user, agent.user
    assert_equal "Ticket Admin", agent.name
    assert_equal "TicketAdmin", agent.agent_class_name
    assert_equal "TicketAdminAgent", agent.telemetry_agent_class
    assert agent.active?
    assert_equal AdminAgentScaffold::SCAFFOLD_TOOLS, agent.tools
    assert_equal [ "rails" ], agent.instruction_sets
    assert_equal "computerUse", agent.preset_type
    assert_equal agent, @resource.reload.agent
  end

  test "instructions carry the reported schema" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    assert_includes agent.instructions, "Ticket"
    assert_includes agent.instructions, "tickets"
    assert_includes agent.instructions, "subject: string, required"
    assert_includes agent.instructions, "status: string, required, default: open"
    assert_includes agent.instructions, "has_many replies (Reply)"
    assert_includes agent.instructions, "1042"
    assert_includes agent.instructions, @resource.schema_fingerprint
  end

  test "resource without an admin UI gets the agent-driven surface rule" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    assert_includes agent.instructions, "no admin dashboard"
    assert_includes agent.instructions, "without the admin UI"
  end

  test "resource with an admin UI is told to drive it" do
    @resource.update!(admin_route: "/admin/tickets")
    agent = AdminAgentScaffold.call(@resource, user: @user)

    assert_includes agent.instructions, "/admin/tickets"
  end

  test "scaffolds CRUD action prompts with read-only actions exposed as tools" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    names = agent.action_prompts.map { |ap| ap["name"] }
    assert_equal %w[list_records inspect_record create_record update_record archive_record], names

    exposed = agent.action_prompts.select { |ap| ap["expose_as_tool"] }.map { |ap| ap["name"] }
    assert_equal %w[list_records inspect_record], exposed

    assert_equal [ Agent::DEFAULT_ACTION, *names ], agent.available_actions
  end

  test "regeneration updates the same agent and versions the change" do
    agent = AdminAgentScaffold.call(@resource, user: @user)
    assert_equal 1, agent.version_count

    @resource.update!(columns: [ { "name" => "subject", "type" => "string" }, { "name" => "priority", "type" => "integer" } ])
    regenerated = AdminAgentScaffold.call(@resource.reload, user: @user)

    assert_equal agent.id, regenerated.id
    assert_includes regenerated.instructions, "priority: integer"
    assert_equal 2, regenerated.version_count, "schema change should create a new agent version"
  end

  test "regeneration preserves user-tuned provider and model" do
    agent = AdminAgentScaffold.call(@resource, user: @user)
    agent.update!(provider: "anthropic", model: "claude-haiku-4-5")

    regenerated = AdminAgentScaffold.call(@resource.reload, user: @user)

    assert_equal "anthropic", regenerated.provider
    assert_equal "claude-haiku-4-5", regenerated.model
  end

  test "two resources scaffold two distinct agents with unique slugs" do
    other = AdminResource.register_report!(
      account: @account,
      service_name: "support_inbox",
      payload: { "name" => "Reply", "table_name" => "replies" }
    )

    ticket_agent = AdminAgentScaffold.call(@resource, user: @user)
    reply_agent = AdminAgentScaffold.call(other, user: @user)

    assert_not_equal ticket_agent.id, reply_agent.id
    assert_not_equal ticket_agent.slug, reply_agent.slug
  end

  test "exported class code carries a single Agent suffix" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    assert_includes agent.to_agent_class_code, "class TicketAdminAgent < ApplicationAgent"
    assert_not_includes agent.to_agent_class_code, "AgentAgent"
  end

  test "the same model name in two services gets service-qualified identities" do
    other = AdminResource.register_report!(
      account: @account,
      service_name: "billing_portal",
      payload: { "name" => "Ticket", "table_name" => "tickets" }
    )

    billing_agent = AdminAgentScaffold.call(other, user: @user)
    inbox_agent = AdminAgentScaffold.call(@resource.reload, user: @user)

    assert_includes billing_agent.name, "billing_portal"
    assert_equal "BillingPortalTicketAdmin", billing_agent.agent_class_name
    assert_equal "SupportInboxTicketAdmin", inbox_agent.agent_class_name
    assert_not_equal billing_agent.telemetry_agent_class, inbox_agent.telemetry_agent_class
  end

  test "deleting a generated agent nullifies the resource link and allows regeneration" do
    agent = AdminAgentScaffold.call(@resource, user: @user)

    agent.destroy!
    assert_nil @resource.reload.agent_id

    regenerated = AdminAgentScaffold.call(@resource, user: @user)
    assert regenerated.persisted?
    assert_not_equal agent.id, regenerated.id
    assert_equal regenerated.id, @resource.reload.agent_id
  end
end
