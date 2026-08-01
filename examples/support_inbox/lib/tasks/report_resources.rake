# frozen_string_literal: true

# Reports this app's ActiveRecord resource manifest to the ActiveAgents
# platform (POST /v1/resources — the sibling of telemetry ingest), so the
# dashboard's Admin Agents view can scaffold one admin agent per model the
# way rails_admin scaffolds admin screens.
#
#   ACTIVEAGENTS_API_KEY=<workspace key> bin/rails active_agent:report_resources
#
# Uses the same credentials as telemetry. Reports are idempotent full
# snapshots — run it again after a migration to refresh the manifest.
namespace :active_agent do
  desc "Report ActiveRecord resources to the ActiveAgents platform for admin-agent scaffolding"
  task report_resources: :environment do
    api_key = ENV["ACTIVEAGENTS_API_KEY"].to_s.strip
    abort "Set ACTIVEAGENTS_API_KEY (your workspace key from the Organization page)" if api_key.empty?

    endpoint = URI(
      ENV.fetch(
        "ACTIVEAGENTS_RESOURCES_ENDPOINT",
        ENV.fetch("ACTIVEAGENTS_TELEMETRY_ENDPOINT", "https://api.activeagents.ai/v1/traces").sub(%r{/traces/?\z}, "/resources")
      )
    )
    unless endpoint.path.end_with?("/resources")
      abort "Cannot derive the resources endpoint from #{endpoint} — set ACTIVEAGENTS_RESOURCES_ENDPOINT explicitly"
    end

    Rails.application.eager_load!

    resources = ApplicationRecord.descendants.reject(&:abstract_class?).filter_map do |model|
      next unless model.table_exists?

      route_key = model.model_name.route_key
      admin_route = Rails.application.routes.url_helpers.respond_to?("admin_#{route_key}_path") ? "/admin/#{route_key}" : nil

      {
        name: model.name,
        table_name: model.table_name,
        columns: model.columns.map do |column|
          { name: column.name, type: column.type, null: column.null, default: column.default }
        end,
        associations: model.reflect_on_all_associations.map do |reflection|
          {
            kind: reflection.macro,
            name: reflection.name,
            class_name: (reflection.class_name rescue nil)
          }
        end,
        record_count: (model.count rescue nil),
        admin_route: admin_route
      }
    end

    # Matches telemetry.service_name in config/active_agent.yml so reported
    # resources land next to this app's traces on the platform.
    payload = {
      service_name: ENV.fetch("ACTIVEAGENTS_SERVICE_NAME", "support_inbox"),
      environment: Rails.env,
      resources: resources
    }

    response = Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: endpoint.scheme == "https") do |http|
      request = Net::HTTP::Post.new(endpoint.request_uri, {
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json"
      })
      request.body = payload.to_json
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      body = JSON.parse(response.body) rescue {}
      puts "Reported #{resources.size} resources for #{payload[:service_name]} (registered: #{body['registered']})"
      puts "Open the dashboard's Admin Agents view to generate admin agents."
    else
      abort "Report failed: HTTP #{response.code} #{response.body.to_s.byteslice(0, 500)}"
    end
  end
end
