# frozen_string_literal: true

module Api
  module V1
    # Collector for evaluation reports an application ran itself
    # (POST /v1/evaluations, ActiveAgent::Evals::Publisher's default endpoint).
    # Authenticated with the same account keys as trace ingest; the report is
    # stored by ExternalEvaluationImport.
    #
    # Responds 201 with the receipt the publisher checks, 200 for an identical
    # retry, 409 for different content under a run_id already stored, 413 over
    # the size limit, 429 over the account's trace quota, its observed-agent cap
    # or the request rate, and 400 or 422 for a body that is not a valid report.
    class EvaluationsController < ActionController::API
      wrap_parameters false

      before_action :authenticate_account!
      before_action :enforce_trace_quota
      rate_limit to: 30, within: 1.minute, by: -> { @account.id }

      def create
        return report_too_large if request.content_length.to_i > ExternalEvaluationImport::MAX_BYTES

        body = request.body.read(ExternalEvaluationImport::MAX_BYTES + 1).to_s
        return report_too_large if body.bytesize > ExternalEvaluationImport::MAX_BYTES

        run, duplicate = ExternalEvaluationImport.call(account: @account, payload: JSON.parse(body))
        render json: receipt(run, duplicate), status: duplicate ? :ok : :created
      rescue JSON::ParserError
        render json: { error: "Invalid JSON" }, status: :bad_request
      rescue ExternalEvaluationImport::Invalid, ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ExternalEvaluationImport::Conflict => e
        render json: { error: e.message }, status: :conflict
      rescue ExternalEvaluationImport::LimitExceeded => e
        render json: { error: e.message }, status: :too_many_requests
      end

      private

      def authenticate_account!
        token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
        return render(json: { error: "Missing Authorization header" }, status: :unauthorized) if token.blank?

        @account = Account.authenticate_api_token(token)
        render json: { error: "Invalid API key" }, status: :unauthorized if @account.nil?
      end

      # An account over its plan's trace quota imports no reports either.
      def enforce_trace_quota
        return if @account.can_ingest_traces?

        render json: { error: "Trace quota exceeded for current plan", limit: @account.effective_trace_limit }, status: :too_many_requests
      end

      # `url` is relative to this host: the dashboard page that shows the run.
      def receipt(run, duplicate)
        {
          id: run.id,
          evaluation_id: run.evaluation_id,
          run_id: run.external_run_id,
          status: run.status,
          duplicate: duplicate,
          url: "/dashboard/evaluations?evaluation=#{run.evaluation_id}&run=#{run.id}"
        }
      end

      def report_too_large
        render json: { error: "Report exceeds #{ExternalEvaluationImport::MAX_BYTES / 1.megabyte} MiB" }, status: :content_too_large
      end
    end
  end
end
