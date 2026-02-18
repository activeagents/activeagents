# frozen_string_literal: true

class AddUserToAgents < ActiveRecord::Migration[8.0]
  def change
    add_reference :agents, :user, null: true, foreign_key: true
    add_index :agents, [ :user_id, :slug ], unique: true
  end
end
