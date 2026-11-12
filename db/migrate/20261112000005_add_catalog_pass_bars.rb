# frozen_string_literal: true

# A catalog product's and a set's pass bars (min_pass_rate, threshold,
# gated), kept through import so dashboard runs are held to them.
#
# Copied from the engine's install generator (migration 035, 1.9.8) with the
# platform's empty table prefix, the way the other 1.9 migrations were.
class AddCatalogPassBars < ActiveRecord::Migration[8.2]
  def up
    type = connection.adapter_name.to_s.downcase.include?("postgres") ? :jsonb : :json
    catalog_tables.each do |table|
      next unless table_exists?(table)
      next if column_exists?(table, :pass)

      add_column table, :pass, type
    end
  end

  def down
    catalog_tables.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :pass)

      remove_column table, :pass
    end
  end

  private

  def catalog_tables
    %w[scenario_products scenario_sets].map { |table| "#{ActionAgent.table_name_prefix}#{table}" }
  end
end
