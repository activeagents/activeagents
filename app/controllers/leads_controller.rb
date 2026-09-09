# frozen_string_literal: true

class LeadsController < ApplicationController
  allow_unauthenticated_access

  def create
    @lead = Lead.new(lead_params)

    if @lead.save
      LeadMailer.notification(@lead).deliver_later
      LeadMailer.confirmation(@lead).deliver_later
      @lead.update_column(:notified_at, Time.current)

      SyncLeadToResendJob.perform_later(@lead.id)

      respond_to do |format|
        format.json { render json: { success: true, message: "Thanks — we'll be in touch within one business day." } }
        format.html { redirect_to root_path(anchor: "services"), notice: "Thanks — we'll be in touch within one business day." }
      end
    else
      respond_to do |format|
        format.json { render json: { error: @lead.errors.full_messages.first || "Something went wrong." }, status: :unprocessable_entity }
        format.html { redirect_to root_path(anchor: "contact"), alert: @lead.errors.full_messages.first || "Something went wrong." }
      end
    end
  end

  private

  def lead_params
    params.permit(:name, :email, :company, :service_type, :message, :source)
  end
end
