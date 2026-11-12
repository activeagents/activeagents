# frozen_string_literal: true

# A catalog product's named criteria lists, kept through import.
#
# Copied from the engine's install generator (migration 034, 1.9.8; 033 is
# unused) with the platform's empty table prefix, the way the other 1.9
# migrations were.
class AddCatalogProductCriteria < ActiveRecord::Migration[8.2]
  def up
    return unless table_exists?(products_table)
    return if column_exists?(products_table, :criteria)

    type = connection.adapter_name.to_s.downcase.include?("postgres") ? :jsonb : :json
    add_column products_table, :criteria, type
  end

  def down
    return unless table_exists?(products_table)
    return unless column_exists?(products_table, :criteria)

    remove_column products_table, :criteria
  end

  private

  def products_table
    "#{ActionAgent.table_name_prefix}scenario_products"
  end
end
