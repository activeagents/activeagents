# frozen_string_literal: true

# Agents discovered by watching telemetry rather than authored in the UI.
#
# `agent_class` on a trace was a bare string with no link to `agents`, so an
# app reporting traces showed runs in Traces and Interactions while the Agents
# list stayed empty. These columns let ingest find-or-create the agent behind a
# trace and attach the trace to it.
class AddObservedAgentRegistration < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :service_name, :string
    add_column :agents, :action_name, :string
    add_column :agents, :source, :string
    add_column :agents, :first_observed_at, :datetime
    add_column :agents, :last_observed_at, :datetime

    # One agent per (app, class, action). Clara.respond and Clara.title are
    # different agents — different instructions, tools, and cost — that share a
    # class name because one app method spawns both.
    add_index :agents,
              %i[user_id service_name agent_class_name action_name],
              unique: true,
              where: "service_name IS NOT NULL",
              name: "index_agents_on_observed_identity"

    # Nullable: existing traces predate registration, and a trace whose agent
    # can't be resolved must still ingest.
    add_reference :active_agent_telemetry_traces, :agent, foreign_key: true, index: true, null: true
  end
end
