# frozen_string_literal: true

module Api
  class UsageController < BaseController
    # Allow anonymous users - they'll get default free tier limits
    allow_unauthenticated_access

    # GET /api/usage
    # Returns current usage stats for the user's account
    def show
      account = current_user&.primary_account

      unless account
        free_limit = Account::USAGE_LIMITS["free"]
        return render json: {
          usage: {
            runs_used: 0,
            runs_limit: free_limit,
            runs_remaining: free_limit,
            can_run: true,
            plan: "free"
          }
        }
      end

      render json: { usage: account.usage_stats }
    end

    # POST /api/usage/check
    # Check if user can run and optionally increment usage
    def check
      account = current_user&.primary_account

      unless account
        return render json: {
          can_run: true,
          usage: { runs_used: 0, runs_limit: Account::USAGE_LIMITS["free"], runs_remaining: Account::USAGE_LIMITS["free"], plan: "free" },
          message: "Create an account to track usage"
        }
      end

      if account.can_run_agent?
        # Increment usage if increment param is true
        account.increment_agent_runs! if params[:increment].to_s == "true"

        render json: {
          can_run: true,
          usage: account.usage_stats
        }
      else
        render json: {
          can_run: false,
          usage: account.usage_stats,
          upgrade_required: true,
          message: "You've reached your plan limit. Upgrade to continue.",
          # A navigable GET page — checkout itself is POST-only
          upgrade_url: "/pricing"
        }, status: :payment_required
      end
    end
  end
end
