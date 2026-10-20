# frozen_string_literal: true

# Interaction feedback (activeagent 1.9.1): a thumbs up or down, with an
# optional comment, on a trace or one of its response spans, submitted by
# the application through the telemetry ingest key and reviewed in the
# dashboard's Interactions.
#
# Copied from the engine's install generator (migration 027) with the
# platform's empty table prefix, the way the other 1.9 migrations were.
class CreateActiveAgentInteractionFeedbacks < ActiveRecord::Migration[8.2]
  def change
    create_table "#{ActionAgent.table_name_prefix}interaction_feedbacks" do |t|
      t.references :telemetry_trace, null: false, foreign_key: { to_table: :active_agent_telemetry_traces, on_delete: :cascade }
      t.string :feedback_id, null: false, limit: 128
      t.string :rating, null: false, limit: 16
      t.string :span_id, limit: 128
      t.string :user_reference, limit: 255
      t.text :comment
      t.timestamps
    end
    add_index "#{ActionAgent.table_name_prefix}interaction_feedbacks",
      [ :telemetry_trace_id, :feedback_id ], unique: true, name: "index_feedback_on_trace_and_feedback_id"
  end
end
