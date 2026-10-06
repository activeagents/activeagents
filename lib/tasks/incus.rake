# frozen_string_literal: true

namespace :incus do
  desc "Check Incus authentication, project and profile without creating a container"
  task preflight: :environment do
    puts JSON.pretty_generate(IncusSandboxService.new.preflight)
  rescue IncusSandboxService::ConnectionError, Faraday::Error, SystemCallError, OpenSSL::OpenSSLError => e
    abort "Incus preflight failed: #{e.message}"
  end
end
