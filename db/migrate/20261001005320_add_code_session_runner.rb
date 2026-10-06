# frozen_string_literal: true

# The 1.8.1 engine records which coding agent ran a code session (Claude Code
# or Codex) and that runner's own session id. Existing sessions stay Claude
# Code sessions.
class AddCodeSessionRunner < ActiveRecord::Migration[8.1]
  def change
    add_column :code_sessions, :runner, :string, null: false, default: "claude_code" unless column_exists?(:code_sessions, :runner)
    add_column :code_sessions, :runner_session_id, :string unless column_exists?(:code_sessions, :runner_session_id)
  end
end
