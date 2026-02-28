module Admin
  class InvestorDocumentsController < BaseController
    before_action :set_document, only: [ :show, :edit, :update, :destroy, :analytics ]

    def index
      @documents = @account.investor_documents.with_attached_file.order(created_at: :desc)

      render inertia: "Admin/Documents/Index", props: {
        documents: @documents.map { |d| document_props(d) },
        document_types: InvestorDocument::DOCUMENT_TYPES
      }
    end

    def show
      render inertia: "Admin/Documents/Show", props: {
        document: document_props(@document, include_details: true),
        access_grants: @document.document_access_grants.includes(:investor).map { |g| grant_props(g) },
        investors: @account.investors.where.not(id: @document.authorized_investors.pluck(:id)).map { |i| { id: i.id, name: i.name, email: i.email } }
      }
    end

    def new
      render inertia: "Admin/Documents/Form", props: {
        document: nil,
        document_types: InvestorDocument::DOCUMENT_TYPES,
        safe_agreements: @account.safe_agreements.includes(:investor).map { |s| { id: s.id, investor_name: s.investor.name, amount: s.investment_amount.to_f } }
      }
    end

    def edit
      render inertia: "Admin/Documents/Form", props: {
        document: document_props(@document),
        document_types: InvestorDocument::DOCUMENT_TYPES,
        safe_agreements: @account.safe_agreements.includes(:investor).map { |s| { id: s.id, investor_name: s.investor.name, amount: s.investment_amount.to_f } }
      }
    end

    def create
      @document = @account.investor_documents.build(document_params)

      if @document.save
        # Grant access to all investors if public
        if @document.public_to_all_investors
          notify_all_investors(@document)
        end
        redirect_to admin_investor_document_path(@document), notice: "Document uploaded successfully"
      else
        render inertia: "Admin/Documents/Form", props: {
          document: document_params.to_h,
          document_types: InvestorDocument::DOCUMENT_TYPES,
          safe_agreements: @account.safe_agreements.includes(:investor).map { |s| { id: s.id, investor_name: s.investor.name, amount: s.investment_amount.to_f } },
          errors: @document.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def update
      if @document.update(document_params)
        redirect_to admin_investor_document_path(@document), notice: "Document updated"
      else
        render inertia: "Admin/Documents/Form", props: {
          document: document_props(@document),
          document_types: InvestorDocument::DOCUMENT_TYPES,
          errors: @document.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def destroy
      @document.destroy
      redirect_to admin_investor_documents_path, notice: "Document deleted"
    end

    def analytics
      logs = @document.document_access_logs.includes(:investor)

      render inertia: "Admin/Documents/Analytics", props: {
        document: document_props(@document),
        analytics: {
          total_views: logs.views.count,
          total_downloads: logs.downloads.count,
          unique_viewers: logs.select(:investor_id).distinct.count,
          views_by_day: logs.views.group("DATE(created_at)").count.transform_keys(&:to_s),
          recent_access: logs.recent.limit(50).map { |l| log_props(l) }
        }
      }
    end

    private

    def set_document
      @document = @account.investor_documents.find(params[:id])
    end

    def document_params
      params.require(:investor_document).permit(
        :name, :document_type, :description, :version,
        :public_to_all_investors, :requires_accreditation,
        :safe_agreement_id, :file
      )
    end

    def document_props(document, include_details: false)
      props = {
        id: document.id,
        name: document.name,
        document_type: document.document_type,
        document_type_label: document.document_type_label,
        description: document.description,
        version: document.version,
        public_to_all_investors: document.public_to_all_investors,
        view_count: document.view_count,
        download_count: document.download_count,
        created_at: document.created_at
      }

      if document.file.attached?
        props[:file] = {
          filename: document.file.filename.to_s,
          content_type: document.file.content_type,
          byte_size: document.file.byte_size
        }
      end

      if include_details
        props[:requires_accreditation] = document.requires_accreditation
        props[:safe_agreement_id] = document.safe_agreement_id
        props[:unique_viewers] = document.unique_viewers_count
      end

      props
    end

    def grant_props(grant)
      {
        id: grant.id,
        investor: {
          id: grant.investor.id,
          name: grant.investor.name,
          email: grant.investor.email
        },
        granted_at: grant.granted_at,
        expires_at: grant.expires_at,
        active: grant.active?
      }
    end

    def log_props(log)
      {
        id: log.id,
        investor_name: log.investor.name,
        action: log.action,
        created_at: log.created_at,
        ip_address: log.ip_address
      }
    end

    def notify_all_investors(document)
      @account.investors.with_portal_access.find_each do |investor|
        InvestorMailer.document_shared(investor, document).deliver_later
      end
    end
  end
end
