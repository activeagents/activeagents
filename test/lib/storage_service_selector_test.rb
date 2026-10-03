# frozen_string_literal: true

require "test_helper"

class StorageServiceSelectorTest < ActiveSupport::TestCase
  BUCKET = "acme-recordings-production"
  SIGNER = "recordings-signer-production@acme.iam.gserviceaccount.com"
  GOOGLE_VARIABLES = { "RECORDINGS_BUCKET" => BUCKET, "RECORDINGS_SIGNER_EMAIL" => SIGNER }.freeze

  test "uses Google Cloud Storage once a bucket and a signer are set" do
    assert_equal :google, StorageServiceSelector.service(GOOGLE_VARIABLES)
    assert_not StorageServiceSelector.disk_fallback?(GOOGLE_VARIABLES)
  end

  test "falls back to the local disk while no bucket is set" do
    assert_equal :local, StorageServiceSelector.service({})
    assert StorageServiceSelector.disk_fallback?({})
  end

  test "treats a blank bucket as unset" do
    env = { "RECORDINGS_BUCKET" => "  ", "ACTIVE_STORAGE_SERVICE" => "" }

    assert_equal :local, StorageServiceSelector.service(env)
    assert StorageServiceSelector.disk_fallback?(env)
  end

  test "a bucket without a signer raises, naming the missing variable" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service("RECORDINGS_BUCKET" => BUCKET, "RECORDINGS_SIGNER_EMAIL" => " ")
    end

    assert_match(/RECORDINGS_SIGNER_EMAIL/, error.message)
  end

  test "ACTIVE_STORAGE_SERVICE=local keeps the disk when a bucket is set" do
    env = { "ACTIVE_STORAGE_SERVICE" => "local", "RECORDINGS_BUCKET" => BUCKET }

    assert_equal :local, StorageServiceSelector.service(env)
    assert_not StorageServiceSelector.disk_fallback?(env), "an explicit choice of the disk is not a fallback"
  end

  test "ACTIVE_STORAGE_SERVICE=google uses Google Cloud Storage when a bucket and a signer are set" do
    assert_equal :google, StorageServiceSelector.service(GOOGLE_VARIABLES.merge("ACTIVE_STORAGE_SERVICE" => "Google"))
  end

  test "ACTIVE_STORAGE_SERVICE=google without a bucket raises, naming the missing variable" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service("ACTIVE_STORAGE_SERVICE" => "google", "RECORDINGS_SIGNER_EMAIL" => SIGNER)
    end

    assert_match(/RECORDINGS_BUCKET/, error.message)
  end

  test "ACTIVE_STORAGE_SERVICE=google without a signer raises, naming the missing variable" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service("ACTIVE_STORAGE_SERVICE" => "google", "RECORDINGS_BUCKET" => BUCKET)
    end

    assert_match(/RECORDINGS_SIGNER_EMAIL/, error.message)
  end

  test "ACTIVE_STORAGE_SERVICE naming another service raises" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service(GOOGLE_VARIABLES.merge("ACTIVE_STORAGE_SERVICE" => "test"))
    end

    assert_equal "ACTIVE_STORAGE_SERVICE=test is not a production storage service. Use google or local.", error.message
  end

  test "reads the process environment by default" do
    names = [ "ACTIVE_STORAGE_SERVICE", *GOOGLE_VARIABLES.keys ]
    previous = ENV.to_h.slice(*names)
    ENV["ACTIVE_STORAGE_SERVICE"] = nil
    GOOGLE_VARIABLES.each { |name, value| ENV[name] = value }

    assert_equal :google, StorageServiceSelector.service
  ensure
    names.each { |name| ENV[name] = previous[name] }
  end
end
