module Admin
  class CapTableController < BaseController
    def index
      @entries = @account.cap_table_entries.includes(:investor, :safe_agreement).order(:stakeholder_type, :stakeholder_name)

      # Calculate totals
      total_shares = @entries.equity.sum(:shares).to_i
      total_ownership = @entries.sum(:ownership_percent).to_f

      render inertia: "Admin/CapTable/Index", props: {
        entries: @entries.map { |e| entry_props(e) },
        summary: {
          total_shares: total_shares,
          total_ownership: total_ownership,
          by_type: {
            founders: @entries.founders.sum(:ownership_percent).to_f,
            investors: @entries.investors.sum(:ownership_percent).to_f,
            employees: @entries.by_stakeholder_type("employee").sum(:ownership_percent).to_f,
            advisors: @entries.by_stakeholder_type("advisor").sum(:ownership_percent).to_f
          },
          by_security: {
            common: @entries.by_security_type("common").sum(:shares).to_i,
            preferred: @entries.by_security_type("preferred").sum(:shares).to_i,
            options: @entries.options.sum(:shares).to_i,
            safes: @account.safe_agreements.where(status: "signed").sum(:investment_amount).to_f
          }
        },
        pending_safes: @account.safe_agreements.where(status: "signed").includes(:investor).map do |safe|
          {
            id: safe.id,
            investor_name: safe.investor.name,
            investment_amount: safe.investment_amount.to_f,
            valuation_cap: safe.valuation_cap&.to_f,
            safe_type: safe.safe_type
          }
        end
      }
    end

    private

    def entry_props(entry)
      {
        id: entry.id,
        stakeholder_name: entry.stakeholder_name,
        stakeholder_type: entry.stakeholder_type,
        stakeholder_type_label: entry.stakeholder_type_label,
        security_type: entry.security_type,
        security_class: entry.security_class,
        security_label: entry.security_label,
        shares: entry.shares&.to_i,
        ownership_percent: entry.ownership_percent&.to_f,
        vested_shares: entry.vested_shares&.to_i,
        vested_percent: entry.vested_percent,
        exercise_price: entry.exercise_price&.to_f,
        grant_date: entry.grant_date,
        expiration_date: entry.expiration_date,
        investor_id: entry.investor_id
      }
    end
  end
end
