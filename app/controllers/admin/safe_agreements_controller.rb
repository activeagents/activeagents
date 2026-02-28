module Admin
  class SafeAgreementsController < BaseController
    before_action :set_safe, only: [ :show, :edit, :update, :destroy, :send_for_signature, :mark_signed, :convert, :cancel ]

    def index
      @safes = @account.safe_agreements.includes(:investor).order(created_at: :desc)

      render inertia: "Admin/SafeAgreements/Index", props: {
        safe_agreements: @safes.map { |s| safe_props(s) },
        summary: {
          total_amount: @safes.sum(:investment_amount).to_f,
          by_status: @safes.group(:status).count,
          signed_amount: @safes.where(status: %w[signed converted]).sum(:investment_amount).to_f
        },
        investors: @account.investors.map { |i| { id: i.id, name: i.name } }
      }
    end

    def show
      render inertia: "Admin/SafeAgreements/Show", props: {
        safe_agreement: safe_props(@safe, include_details: true),
        investor: {
          id: @safe.investor.id,
          name: @safe.investor.name,
          email: @safe.investor.email
        },
        documents: @safe.investor_documents.map { |d| { id: d.id, name: d.name, document_type: d.document_type } }
      }
    end

    def new
      investor_id = params[:investor_id]

      render inertia: "Admin/SafeAgreements/Form", props: {
        safe_agreement: nil,
        investors: @account.investors.map { |i| { id: i.id, name: i.name, email: i.email } },
        selected_investor_id: investor_id&.to_i,
        safe_types: %w[post_money pre_money mfn]
      }
    end

    def edit
      render inertia: "Admin/SafeAgreements/Form", props: {
        safe_agreement: safe_props(@safe),
        investors: @account.investors.map { |i| { id: i.id, name: i.name, email: i.email } },
        selected_investor_id: @safe.investor_id,
        safe_types: %w[post_money pre_money mfn]
      }
    end

    def create
      @safe = @account.safe_agreements.build(safe_params)

      if @safe.save
        redirect_to admin_safe_agreement_path(@safe), notice: "SAFE agreement created"
      else
        render inertia: "Admin/SafeAgreements/Form", props: {
          safe_agreement: safe_params.to_h,
          investors: @account.investors.map { |i| { id: i.id, name: i.name, email: i.email } },
          safe_types: %w[post_money pre_money mfn],
          errors: @safe.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def update
      if @safe.update(safe_params)
        redirect_to admin_safe_agreement_path(@safe), notice: "SAFE agreement updated"
      else
        render inertia: "Admin/SafeAgreements/Form", props: {
          safe_agreement: safe_props(@safe),
          investors: @account.investors.map { |i| { id: i.id, name: i.name, email: i.email } },
          safe_types: %w[post_money pre_money mfn],
          errors: @safe.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def destroy
      @safe.destroy
      redirect_to admin_safe_agreements_path, notice: "SAFE agreement deleted"
    end

    def send_for_signature
      previous_status = @safe.status
      @safe.mark_as_sent!
      InvestorMailer.safe_status_update(@safe.investor, @safe, previous_status).deliver_later
      redirect_to admin_safe_agreement_path(@safe), notice: "SAFE sent for signature"
    end

    def mark_signed
      previous_status = @safe.status
      @safe.mark_as_signed!
      InvestorMailer.safe_status_update(@safe.investor, @safe, previous_status).deliver_later
      redirect_to admin_safe_agreement_path(@safe), notice: "SAFE marked as signed"
    end

    def convert
      previous_status = @safe.status
      @safe.convert!(
        shares: params[:shares].to_i,
        price_per_share: params[:price_per_share].to_f,
        round_name: params[:round_name]
      )
      InvestorMailer.safe_status_update(@safe.investor, @safe, previous_status).deliver_later
      redirect_to admin_safe_agreement_path(@safe), notice: "SAFE converted to equity"
    rescue => e
      redirect_to admin_safe_agreement_path(@safe), alert: "Error converting SAFE: #{e.message}"
    end

    def cancel
      @safe.cancel!
      redirect_to admin_safe_agreement_path(@safe), notice: "SAFE cancelled"
    end

    private

    def set_safe
      @safe = @account.safe_agreements.find(params[:id])
    end

    def safe_params
      params.require(:safe_agreement).permit(
        :investor_id, :investment_amount, :valuation_cap, :discount_percent,
        :safe_type, :pro_rata_rights, :atlas_safe_id
      )
    end

    def safe_props(safe, include_details: false)
      props = {
        id: safe.id,
        investor_id: safe.investor_id,
        investor_name: safe.investor.name,
        investment_amount: safe.investment_amount.to_f,
        valuation_cap: safe.valuation_cap&.to_f,
        discount_percent: safe.discount_percent&.to_f,
        safe_type: safe.safe_type,
        pro_rata_rights: safe.pro_rata_rights,
        status: safe.status,
        display_status: safe.display_status,
        created_at: safe.created_at
      }

      if include_details
        props.merge!(
          sent_at: safe.sent_at,
          signed_at: safe.signed_at,
          converted_at: safe.converted_at,
          cancelled_at: safe.cancelled_at,
          conversion_shares: safe.conversion_shares&.to_i,
          conversion_price_per_share: safe.conversion_price_per_share&.to_f,
          conversion_round_name: safe.conversion_round_name,
          atlas_safe_id: safe.atlas_safe_id
        )
      end

      props
    end
  end
end
