# frozen_string_literal: true

require "test_helper"

class StorageConfigurationTest < ActiveSupport::TestCase
  BUCKET = "acme-recordings-staging"
  SIGNER = "recordings-signer-staging@acme.iam.gserviceaccount.com"

  test "google reads its bucket and URL signer from the environment and names no keyfile" do
    google = storage_configuration("RECORDINGS_BUCKET" => BUCKET, "RECORDINGS_SIGNER_EMAIL" => SIGNER)["google"]

    assert_equal({ "service" => "GCS", "bucket" => BUCKET, "iam" => true, "gsa_email" => SIGNER }, google)
  end

  test "google leaves the signer to the service account when none is set" do
    google = storage_configuration("RECORDINGS_BUCKET" => BUCKET, "RECORDINGS_SIGNER_EMAIL" => nil)["google"]

    assert_nil google["gsa_email"]
  end

  test "google builds a GCS service without contacting Google" do
    configurations = storage_configuration("RECORDINGS_BUCKET" => BUCKET, "RECORDINGS_SIGNER_EMAIL" => SIGNER)
    service = ActiveStorage::Service.configure(:google, configurations)

    assert_instance_of ActiveStorage::Service::GCSService, service
  end

  test "a blob stored on the disk still resolves its service" do
    blob = ActiveStorage::Blob.new(service_name: "local")

    assert_instance_of ActiveStorage::Service::DiskService, blob.service
    assert_equal Rails.root.join("storage").to_s, blob.service.root
  end

  private
    def storage_configuration(env)
      previous = ENV.to_h.slice(*env.keys)
      env.each { |key, value| ENV[key] = value }
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml"))
    ensure
      env.each_key { |key| ENV[key] = previous[key] }
    end
end
