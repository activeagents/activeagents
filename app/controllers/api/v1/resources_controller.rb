# frozen_string_literal: true

module Api
  module V1
    # Resource-manifest ingestion endpoint (POST /v1/resources) — the
    # sibling of telemetry ingest on the same Bearer plane. A connected app
    # running the activeagent gem (with the telemetry + solid_agent extras)
    # reports its ActiveRecord models here so the platform can scaffold
    # admin agents around them, the way rails_admin scaffolds admin screens.
    #
    # @example Request
    #   POST /v1/resources
    #   Authorization: Bearer <api key>
    #   Content-Type: application/json
    #
    #   {
    #     "service_name": "support_inbox",
    #     "environment": "production",
    #     "resources": [
    #       {
    #         "name": "Ticket",
    #         "table_name": "tickets",
    #         "columns": [ { "name": "subject", "type": "string", "null": false } ],
    #         "associations": [ { "kind": "has_many", "name": "replies", "class_name": "Reply" } ],
    #         "record_count": 1042,
    #         "admin_route": null
    #       }
    #     ]
    #   }
    #
    # Reports are idempotent full snapshots keyed on (account, service_name,
    # resource name); re-reporting refreshes columns/associations/counts.
    class ResourcesController < ActionController::API
      include IngestAuthentication

      before_action :authenticate_api_key!

      # A connected app reporting more models than this is almost certainly
      # a misconfigured reporter, and unbounded manifests would let one
      # request create unbounded rows (same cardinality concern as agent
      # auto-registration).
      MAX_RESOURCES_PER_REQUEST = 200

      # POST /v1/resources
      def create
        service_name = params.require(:service_name).to_s.strip
        resources = Array(params[:resources]).take(MAX_RESOURCES_PER_REQUEST)
        environment = params[:environment].presence

        registered = resources.filter_map do |resource|
          payload = resource.respond_to?(:to_unsafe_h) ? resource.to_unsafe_h : resource
          next log_skip(service_name, "entry is not an object") unless payload.is_a?(Hash)

          AdminResource.register_report!(
            account: @account,
            service_name: service_name,
            environment: environment,
            payload: payload
          )
        rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          log_skip(service_name, e.message)
        end

        render json: { service_name: service_name, registered: registered.size }, status: :ok
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :bad_request
      rescue StandardError => e
        Rails.logger.error("[Api::V1::Resources] Ingestion error: #{e.message}")
        render json: { error: "Internal server error" }, status: :internal_server_error
      end

      private

      # Reported strings are attacker-controlled — flatten whitespace so a
      # crafted name can't forge log lines, and keep messages bounded.
      def log_skip(service_name, message)
        detail = "#{service_name}: #{message}".gsub(/\s+/, " ").truncate(300)
        Rails.logger.warn("[Api::V1::Resources] Skipped resource for #{detail}")
        nil
      end
    end
  end
end
