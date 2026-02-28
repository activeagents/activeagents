module Api
  module Admin
    class InvestorsController < BaseController
      before_action :set_investor, only: [ :show, :update, :destroy, :send_portal_invite ]

      def index
        investors = @account.investors.includes(:safe_agreements).order(created_at: :desc)
        render json: {
          investors: investors.map { |i| investor_json(i) },
          summary: {
            total_investors: @account.investors.count,
            total_invested: @account.safe_agreements.where(status: %w[signed converted]).sum(:investment_amount).to_f,
            pending_signatures: @account.safe_agreements.where(status: "sent").count
          }
        }
      end

      def show
        render json: {
          investor: investor_json(@investor, include_details: true),
          safe_agreements: @investor.safe_agreements.map { |s| safe_json(s) }
        }
      end

      def create
        investor = @account.investors.build(investor_params)
        if investor.save
          render json: { investor: investor_json(investor) }, status: :created
        else
          render json: { errors: investor.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @investor.update(investor_params)
          render json: { investor: investor_json(@investor) }
        else
          render json: { errors: @investor.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @investor.destroy
        render json: { success: true }
      end

      def send_portal_invite
        @investor.generate_access_token!
        InvestorMailer.portal_invite(@investor).deliver_later
        render json: { success: true, message: "Portal invite sent" }
      end

      private

      def set_investor
        @investor = @account.investors.find(params[:id])
      end

      def investor_params
        params.require(:investor).permit(
          :name, :email, :legal_name, :phone, :investor_type,
          :entity_name, :entity_type, :portal_enabled,
          :address_line1, :address_line2, :city, :state, :postal_code, :country
        )
      end

      def investor_json(investor, include_details: false)
        json = {
          id: investor.id,
          name: investor.name,
          email: investor.email,
          investor_type: investor.investor_type,
          total_invested: investor.total_invested.to_f,
          safe_count: investor.safe_agreements.count,
          portal_enabled: investor.portal_enabled,
          last_accessed_at: investor.last_accessed_at,
          created_at: investor.created_at
        }

        if include_details
          json.merge!(
            legal_name: investor.legal_name,
            phone: investor.phone,
            entity_name: investor.entity_name,
            entity_type: investor.entity_type,
            address_line1: investor.address_line1,
            address_line2: investor.address_line2,
            city: investor.city,
            state: investor.state,
            postal_code: investor.postal_code,
            country: investor.country,
            access_token_expires_at: investor.access_token_expires_at,
            has_valid_access_token: investor.access_token_valid?
          )
        end

        json
      end

      def safe_json(safe)
        {
          id: safe.id,
          investment_amount: safe.investment_amount.to_f,
          valuation_cap: safe.valuation_cap&.to_f,
          discount_percent: safe.discount_percent&.to_f,
          safe_type: safe.safe_type,
          status: safe.status,
          display_status: safe.display_status,
          signed_at: safe.signed_at,
          created_at: safe.created_at
        }
      end
    end
  end
end
