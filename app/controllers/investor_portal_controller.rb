class InvestorPortalController < ApplicationController
  include InvestorAuthentication

  allow_unauthenticated_access only: [ :login, :authenticate ]
  before_action :require_investor_authentication, except: [ :login, :authenticate ]

  def login
    render inertia: "InvestorPortal/Login", props: {}
  end

  def authenticate
    investor = Investor.find_by(access_token: params[:token])

    if investor&.access_token_valid?
      start_investor_session(investor)
      redirect_to investor_portal_dashboard_path
    else
      redirect_to investor_portal_login_path, alert: "Invalid or expired link. Please contact the company for a new access link."
    end
  end

  def dashboard
    render inertia: "InvestorPortal/Dashboard", props: {
      investor: investor_props(current_investor),
      company: company_props,
      safe_agreements: current_investor.safe_agreements.order(created_at: :desc).map { |s| safe_props(s) },
      documents: accessible_documents_props,
      ownership_summary: ownership_summary_props
    }
  end

  def documents
    render inertia: "InvestorPortal/Documents", props: {
      investor: investor_props(current_investor),
      company: company_props,
      documents: accessible_documents_props
    }
  end

  def show_document
    document = find_accessible_document(params[:id])

    if document
      document.log_access(current_investor, action: "viewed", ip_address: request.remote_ip, user_agent: request.user_agent)

      render inertia: "InvestorPortal/DocumentViewer", props: {
        investor: investor_props(current_investor),
        company: company_props,
        document: document_props(document),
        signed_url: document.file.url(expires_in: 15.minutes)
      }
    else
      redirect_to investor_portal_documents_path, alert: "Document not found or access denied"
    end
  end

  def download_document
    document = find_accessible_document(params[:id])

    if document
      document.log_access(current_investor, action: "downloaded", ip_address: request.remote_ip, user_agent: request.user_agent)
      redirect_to document.file.url(disposition: "attachment", expires_in: 5.minutes), allow_other_host: true
    else
      redirect_to investor_portal_documents_path, alert: "Document not found or access denied"
    end
  end

  def logout
    terminate_investor_session
    redirect_to investor_portal_login_path, notice: "You have been logged out"
  end

  private

  def find_accessible_document(id)
    document = current_investor.account.investor_documents.find_by(id: id)
    return nil unless document
    return document if document.accessible_by?(current_investor)
    nil
  end

  def investor_props(investor)
    {
      id: investor.id,
      name: investor.name,
      email: investor.email,
      total_invested: investor.total_invested.to_f,
      ownership_percent: investor.ownership_summary.to_f
    }
  end

  def company_props
    account = current_investor.account
    {
      name: account.name
    }
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
      converted_at: safe.converted_at,
      conversion_shares: safe.conversion_shares&.to_i,
      conversion_round_name: safe.conversion_round_name
    }
  end

  def accessible_documents_props
    account = current_investor.account
    public_docs = account.investor_documents.public_documents
    granted_doc_ids = current_investor.document_access_grants.active.pluck(:investor_document_id)
    granted_docs = account.investor_documents.where(id: granted_doc_ids)

    (public_docs + granted_docs).uniq.map { |d| document_props(d) }
  end

  def document_props(doc)
    props = {
      id: doc.id,
      name: doc.name,
      document_type: doc.document_type,
      document_type_label: doc.document_type_label,
      description: doc.description,
      version: doc.version,
      created_at: doc.created_at
    }

    if doc.file.attached?
      props[:file] = {
        filename: doc.file.filename.to_s,
        content_type: doc.file.content_type,
        byte_size: doc.file.byte_size
      }
    end

    props
  end

  def ownership_summary_props
    entries = current_investor.cap_table_entries
    {
      total_ownership_percent: entries.sum(:ownership_percent).to_f,
      entries: entries.map do |e|
        {
          security_type: e.security_type,
          security_class: e.security_class,
          security_label: e.security_label,
          shares: e.shares&.to_i,
          ownership_percent: e.ownership_percent&.to_f
        }
      end
    }
  end
end
