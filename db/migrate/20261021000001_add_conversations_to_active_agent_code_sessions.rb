# frozen_string_literal: true

# Makes Claude Code and Codex sessions conversations (activeagent 1.9.3):
# each session is one turn, and a turn after the first names the
# conversation's first session as its root. A conversation resumes the same
# CLI session (resume_session_id), and a turn may carry a note from the
# dashboard ahead of the person's message (context_note), such as who drove
# the browser since the last turn.
#
# Copied from the engine's install generator (migration 028) with the
# platform's empty table prefix, the way the other 1.9 migrations were.
class AddConversationsToActiveAgentCodeSessions < ActiveRecord::Migration[8.2]
  def change
    sessions = "#{ActionAgent.table_name_prefix}code_sessions"
    add_column sessions, :conversation_root_id, :bigint
    add_column sessions, :turn_index, :integer, default: 0, null: false
    add_column sessions, :origin, :string
    add_column sessions, :context_note, :text
    add_column sessions, :resume_session_id, :string
    add_index sessions, :conversation_root_id
  end
end
