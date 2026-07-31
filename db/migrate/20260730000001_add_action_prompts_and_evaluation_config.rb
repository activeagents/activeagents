# frozen_string_literal: true

# Named action prompts: agents can define extra actions, each a system
# prompt stacked on top of the base instructions (mirrors the activeagent
# gem's actions-as-prompts model). Runs record which action executed so
# cohorts and sessions can group by action.
#
# evaluations.config carries evaluation-level settings that aren't
# criteria — first use: compare_models (per-model cohort scoring) and
# judge-defined KPI provenance.
class AddActionPromptsAndEvaluationConfig < ActiveRecord::Migration[8.2]
  def change
    add_column :agents, :action_prompts, :jsonb, default: [], null: false
    add_column :agent_runs, :action_name, :string
    add_column :evaluations, :config, :jsonb, default: {}, null: false
  end
end
