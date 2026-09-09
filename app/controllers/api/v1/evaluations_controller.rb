# frozen_string_literal: true

module Api
  module V1
    class EvaluationsController < ActionController::API
      before_action :authenticate_api_key!

      def create
        # Read a bounded body before JSON parsing, including chunked requests.
        body = request.body.read(ExternalEvaluationImport::MAX_BYTES + 1)
        if body.bytesize > ExternalEvaluationImport::MAX_BYTES
          return render json: { error: "Report exceeds 2 MiB" }, status: :payload_too_large
        end
        run, duplicate = ExternalEvaluationImport.call(account: @account, payload: JSON.parse(body))
        render json: {
          evaluation_id: run.evaluation_id, id: run.id, run_id: run.external_run_id,
          status: run.status, duplicate: duplicate,
          url: "/dashboard/evaluations?evaluation=#{run.evaluation_id}&run=#{run.id}"
        }, status: duplicate ? :ok : :created
      rescue JSON::ParserError
        render json: { error: "Invalid JSON" }, status: :bad_request
      rescue ExternalEvaluationImport::Invalid, ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ExternalEvaluationImport::Conflict => e
        render json: { error: e.message }, status: :conflict
      end

      private

      def authenticate_api_key!
        token = request.headers["Authorization"].to_s[/\ABearer\s+(.+)\z/i, 1]
        return render json: { error: "Missing Authorization header" }, status: :unauthorized if token.blank?

        api_key = ApiKey.authenticate(token)
        @account = api_key ? api_key.account : Account.find_by(telemetry_api_key: token)
        return render json: { error: "Invalid API key" }, status: :unauthorized unless @account

        api_key&.touch_last_used!
      end
    end
  end
end
