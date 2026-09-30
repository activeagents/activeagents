class NewsletterSubscriptionsController < ApplicationController
  allow_unauthenticated_access
  layout "pilot"
  before_action do
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
  rate_limit to: 10, within: 10.minutes, only: :create

  def create
    NewsletterSubscription.subscribe!(params[:email_address])
    respond_to do |format|
      format.json { render json: { success: true, message: "Check your email to confirm your newsletter subscription." } }
      format.html { redirect_to root_path(anchor: "newsletter"), notice: "Check your email to confirm your newsletter subscription." }
    end
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def show
    @subscription = NewsletterSubscription.find_by_token_for(:confirmation, params[:token])
    render plain: "This confirmation link has expired. Subscribe again for a new link.", status: :gone unless @subscription
  end

  def update
    subscription = NewsletterSubscription.find_by_token_for(:confirmation, params[:token])
    return render plain: "This confirmation link is no longer available.", status: :gone unless subscription

    subscription.with_lock do
      return head :gone if subscription.confirmed_at?
      subscription.update!(confirmed_at: Time.current)
      SyncNewsletterToResendJob.perform_later(subscription.id)
    end
    render plain: "Your newsletter subscription is confirmed. You can unsubscribe in any newsletter."
  end
end
