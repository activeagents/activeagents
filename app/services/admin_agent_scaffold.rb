# frozen_string_literal: true

# Scaffolds an admin agent around one reported resource — the agent-driven
# analogue of rails_admin generating admin screens around an ActiveRecord
# model. The result is an ordinary Agent record (reusable, versioned,
# executable, MCP-exposed), whose instructions carry the resource's
# reported schema and whose named actions are the CRUD verbs an admin
# dashboard would render as screens.
#
# Regeneration is rails_admin-like too: scaffold-owned fields (instructions,
# action prompts, tools, class name) are overwritten from the latest
# manifest — Agent's versioning callback records the change — while fields
# the user tunes by hand (provider, model, model_config, appearance) are
# left alone.
class AdminAgentScaffold
  SCAFFOLD_TOOLS = %w[database fetch playwright memory].freeze

  def self.call(resource, user:)
    new(resource, user: user).call
  end

  def initialize(resource, user:)
    @resource = resource
    @user = user
  end

  def call
    agent = @resource.agent || @user.agents.build(
      name: agent_name,
      status: :active
    )

    agent.assign_attributes(
      description: description,
      agent_class_name: agent_class_name,
      preset_type: "computerUse",
      instruction_sets: [ "rails" ],
      tools: SCAFFOLD_TOOLS,
      instructions: instructions,
      action_prompts: action_prompts
    )
    agent.user ||= @user
    agent.save!

    @resource.update!(agent: agent) if @resource.agent_id != agent.id
    agent
  end

  private

  # Two connected apps can both report a "User" model; when that happens
  # the service name joins the identity so the two admin agents stay
  # distinguishable everywhere — names, slugs, and telemetry_agent_class
  # (which would otherwise conflate their traces and evaluations).
  def ambiguous_name?
    @ambiguous_name ||= @resource.account.admin_resources
      .where(name: @resource.name)
      .where.not(service_name: @resource.service_name)
      .exists?
  end

  def agent_name
    base = @resource.name.truncate(55, omission: "")
    ambiguous_name? ? "#{base} Admin (#{@resource.service_name.truncate(30, omission: '')})" : "#{base} Admin"
  end

  # No "Agent" suffix here — Agent#telemetry_agent_class appends it, and
  # to_agent_class_code renders through that method.
  def agent_class_name
    prefix = ambiguous_name? ? @resource.service_name.underscore.camelize.delete("^A-Za-z0-9") : ""
    "#{prefix}#{@resource.name.delete(':')}Admin"
  end

  def description
    "Auto-generated admin agent for the #{@resource.service_name} " \
      "#{@resource.name} resource. Does the work of an admin dashboard " \
      "for #{@resource.table_name.presence || @resource.name.underscore.pluralize} " \
      "through conversation instead of screens."
  end

  def instructions
    <<~INSTRUCTIONS.strip
      You are the admin agent for the #{@resource.name} resource of the #{@resource.service_name} application. You were generated from the app's reported schema the way rails_admin generates an admin UI — you do the work of an admin dashboard through conversation and tools instead of screens.

      ## Resource

      #{schema_section}

      ## How you operate

      - Check the live manifest with the describe_resource tool before reasoning about fields — the schema above is the snapshot you were generated from (fingerprint #{@resource.schema_fingerprint}).
      #{surface_rule}
      - Human in the loop: the operator is present in their own browser session. Propose exact changes and wait for their confirmation before anything destructive or irreversible (deletes, bulk updates) proceeds — hand off rather than guess.
      - Never invent records or attribute values. Everything you state about data must come from a tool result or from the operator.
      - Record durable observations with save_memory so later admin runs — and other agents working on #{@resource.service_name} — inherit what you learned.
    INSTRUCTIONS
  end

  def schema_section
    lines = [ "Model: #{@resource.name}" ]
    lines << "Table: #{@resource.table_name}" if @resource.table_name.present?
    lines << "Records at last report: #{@resource.record_count}" if @resource.record_count.present?

    columns = Array(@resource.columns)
    if columns.any?
      lines << "Columns:"
      columns.each do |column|
        detail = column["type"].to_s
        detail += ", required" if column["null"] == false
        detail += ", default: #{column['default']}" unless column["default"].nil?
        lines << "- #{column['name']}: #{detail}"
      end
    end

    associations = Array(@resource.associations)
    if associations.any?
      lines << "Associations:"
      associations.each do |association|
        target = association["class_name"].present? ? " (#{association['class_name']})" : ""
        lines << "- #{association['kind']} #{association['name']}#{target}"
      end
    end

    lines.join("\n")
  end

  def surface_rule
    if @resource.admin_ui?
      "- The app has an admin UI for this resource at #{@resource.admin_route}. When you drive a browser, work through that UI the way a careful human admin would, and narrate each step so the operator can follow."
    else
      "- The app has no admin dashboard for this resource — you are the admin surface. Operate in web-admin ways without the admin UI: read and reason over reported data, prepare exact changes, and give the operator precise, copy-ready steps for anything you cannot perform directly."
    end
  end

  # The CRUD verbs an admin dashboard renders as screens, as named action
  # prompts. Read-only actions are exposed as MCP tools; mutating ones are
  # deliberately not — they stay behind a human invoking them on purpose.
  def action_prompts
    human = @resource.name.underscore.humanize.downcase
    [
      {
        "name" => "list_records",
        "prompt" => "Produce the index screen of an admin dashboard, in words: summarize the #{human} records relevant to the operator's request as a concise listing with the columns an admin would scan first, and note anything anomalous.",
        "expose_as_tool" => true
      },
      {
        "name" => "inspect_record",
        "prompt" => "Produce the detail screen for one #{human} record: given an identifier, lay out every column value and each associated record that matters, and flag inconsistencies against the schema.",
        "expose_as_tool" => true
      },
      {
        "name" => "create_record",
        "prompt" => "Prepare a new #{human} record: collect every required column, validate the attributes against the schema, present the exact attributes to be created, and wait for the operator's confirmation before treating it as done.",
        "expose_as_tool" => false
      },
      {
        "name" => "update_record",
        "prompt" => "Prepare an update to one #{human} record: identify the record, show current versus proposed values for each changed column, validate against the schema, and wait for the operator's confirmation.",
        "expose_as_tool" => false
      },
      {
        "name" => "archive_record",
        "prompt" => "Prepare removal of one #{human} record: prefer archiving or soft-delete when the schema offers it, spell out exactly what will be removed and what associated records are affected, and require the operator's explicit confirmation — this is destructive.",
        "expose_as_tool" => false
      }
    ]
  end
end
