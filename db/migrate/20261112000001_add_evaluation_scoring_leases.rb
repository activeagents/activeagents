# frozen_string_literal: true

# The scoring lease on an evaluation scenario result: the token a scorer
# holds and when it expires, so a fanned-out run scores each result once.
#
# Copied from the engine's install generator (migration 030, 1.9.7) with the
# platform's empty table prefix, the way the other 1.9 migrations were.
class AddEvaluationScoringLeases < ActiveRecord::Migration[8.2]
  def change
    add_column "#{ActionAgent.table_name_prefix}evaluation_scenario_results", :scoring_token, :string
    add_column "#{ActionAgent.table_name_prefix}evaluation_scenario_results", :scoring_expires_at, :datetime
  end
end
