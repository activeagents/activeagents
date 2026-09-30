# frozen_string_literal: true

module Api
  module V1
    # Collector for evaluation reports an application ran itself
    # (POST /v1/evaluations, ActiveAgent::Evals::Publisher's default endpoint).
    #
    # Validation, storage, idempotency and the status codes are the engine's
    # collector's (ActionAgent::Api::EvaluationReportsController). This
    # subclass takes the same account keys as /v1/traces, and points the
    # receipt at this app's dashboard. The plan's trace quota refuses a new
    # report through ActionAgent.quota_checker (config/initializers/action_agent.rb).
    class EvaluationsController < ActionAgent::Api::EvaluationReportsController
      include Api::AccountTokenAuthentication

      private

      # The engine builds the page's path from the mount the request came
      # through, and this route sits outside it.
      def run_url(run)
        "/dashboard/evaluations?evaluation=#{run.evaluation_id}&run=#{run.id}"
      end
    end
  end
end
