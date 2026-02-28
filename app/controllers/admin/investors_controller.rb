module Admin
  class InvestorsController < BaseController
    before_action :set_investor, only: [ :show, :edit, :update, :destroy, :send_portal_invite, :regenerate_access_token ]

    def index
      @investors = @account.investors.includes(:safe_agreements).order(created_at: :desc)

      render inertia: "Admin/Investors/Index", props: {
        investors: @investors.map { |i| investor_props(i) },
        summary: {
          total_investors: @account.investors.count,
          total_invested: @account.safe_agreements.where(status: %w[signed converted]).sum(:investment_amount).to_f,
          pending_signatures: @account.safe_agreements.where(status: "sent").count
        }
      }
    end

    def show
      render inertia: "Admin/Investors/Show", props: {
        investor: investor_props(@investor, include_details: true),
        safe_agreements: @investor.safe_agreements.order(created_at: :desc).map { |s| safe_props(s) },
        document_access: @investor.document_access_grants.includes(:investor_document).map { |g| grant_props(g) },
        access_logs: @investor.document_access_logs.recent.limit(50).includes(:investor_document).map { |l| log_props(l) }
      }
    end

    def new
      render inertia: "Admin/Investors/Form", props: {
        investor: nil,
        investor_types: Investor::INVESTOR_TYPES
      }
    end

    def edit
      render inertia: "Admin/Investors/Form", props: {
        investor: investor_props(@investor, include_details: true),
        investor_types: %w[individual entity trust]
      }
    end

    def create
      @investor = @account.investors.build(investor_params)

      if @investor.save
        redirect_to admin_investor_path(@investor), notice: "Investor added successfully"
      else
        render inertia: "Admin/Investors/Form", props: {
          investor: investor_params.to_h,
          investor_types: %w[individual entity trust],
          errors: @investor.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def update
      if @investor.update(investor_params)
        redirect_to admin_investor_path(@investor), notice: "Investor updated"
      else
        render inertia: "Admin/Investors/Form", props: {
          investor: investor_props(@investor),
          investor_types: %w[individual entity trust],
          errors: @investor.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def destroy
      @investor.destroy
      redirect_to admin_investors_path, notice: "Investor removed"
    end

    def send_portal_invite
      @investor.generate_access_token!
      InvestorMailer.portal_invite(@investor).deliver_later
      redirect_to admin_investor_path(@investor), notice: "Portal invite sent to #{@investor.email}"
    end

    def regenerate_access_token
      @investor.generate_access_token!
      redirect_to admin_investor_path(@investor), notice: "Access token regenerated"
    end

    private

    def set_investor
      @investor = @account.investors.find(params[:id])
    end

    def investor_params
      params.require(:investor).permit(
        :name, :email, :legal_name, :phone, :investor_type,
        :entity_name, :entity_type, :address_line1, :address_line2,
        :city, :state, :postal_code, :country, :portal_enabled
      )
    end

    def investor_props(investor, include_details: false)
      props = {
        id: investor.id,
        name: investor.name,
        email: investor.email,
        investor_type: investor.investor_type,
        total_invested: investor.total_invested.to_f,
        safe_count: investor.safe_agreements.count,
        portal_enabled: investor.portal_enabled,
        last_accessed_at: investor.last_accessed_at,
        access_token_expires_at: investor.access_token_expires_at,
        created_at: investor.created_at
      }

      if include_details
        props.merge!(
          legal_name: investor.legal_name,
          phone: investor.phone,
          entity_name: investor.entity_name,
          entity_type: investor.entity_type,
          address: {
            line1: investor.address_line1,
            line2: investor.address_line2,
            city: investor.city,
            state: investor.state,
            postal_code: investor.postal_code,
            country: investor.country
          },
          has_valid_access_token: investor.access_token_valid?
        )
      end

      props
    end

    def safe_props(safe)
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

    def grant_props(grant)
      {
        id: grant.id,
        document: {
          id: grant.investor_document.id,
          name: grant.investor_document.name,
          document_type: grant.investor_document.document_type
        },
        granted_at: grant.granted_at,
        expires_at: grant.expires_at,
        active: grant.active?
      }
    end

    def log_props(log)
      {
        id: log.id,
        document_name: log.investor_document.name,
        action: log.action,
        created_at: log.created_at,
        ip_address: log.ip_address
      }
    end
  end
end
