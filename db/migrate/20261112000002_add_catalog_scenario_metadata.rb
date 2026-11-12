# frozen_string_literal: true

# A catalog scenario's extensions, kept through import.
#
# Copied from the engine's install generator (migration 031, 1.9.7) with the
# platform's empty table prefix, the way the other 1.9 migrations were.
class AddCatalogScenarioMetadata < ActiveRecord::Migration[8.2]
  def up
    return unless table_exists?(scenarios_table)
    return if column_exists?(scenarios_table, :metadata)

    type = connection.adapter_name.to_s.downcase.include?("postgres") ? :jsonb : :json
    add_column scenarios_table, :metadata, type
  end

  def down
    return unless table_exists?(scenarios_table)
    return unless column_exists?(scenarios_table, :metadata)

    remove_column scenarios_table, :metadata
  end

  private

  def scenarios_table
    "#{ActionAgent.table_name_prefix}catalog_scenarios"
  end
end
