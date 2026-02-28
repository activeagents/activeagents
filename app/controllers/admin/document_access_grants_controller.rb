module Admin
  class DocumentAccessGrantsController < BaseController
    before_action :set_document

    def create
      investor = @account.investors.find(params[:investor_id])
      grant = @document.grant_access_to(investor, expires_at: params[:expires_at])

      InvestorMailer.document_shared(investor, @document).deliver_later

      redirect_to admin_investor_document_path(@document), notice: "Access granted to #{investor.name}"
    end

    def destroy
      grant = @document.document_access_grants.find(params[:id])
      grant.revoke!

      redirect_to admin_investor_document_path(@document), notice: "Access revoked"
    end

    private

    def set_document
      @document = @account.investor_documents.find(params[:investor_document_id])
    end
  end
end
