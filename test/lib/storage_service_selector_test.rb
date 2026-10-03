# frozen_string_literal: true

require "test_helper"

class StorageServiceSelectorTest < ActiveSupport::TestCase
  BUCKET = "acme-recordings-production"

  test "uses Google Cloud Storage once a bucket is set" do
    env = { "RECORDINGS_BUCKET" => BUCKET }

    assert_equal :google, StorageServiceSelector.service(env)
    assert_not StorageServiceSelector.disk_fallback?(env)
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

  test "ACTIVE_STORAGE_SERVICE=local keeps the disk when a bucket is set" do
    env = { "ACTIVE_STORAGE_SERVICE" => "local", "RECORDINGS_BUCKET" => BUCKET }

    assert_equal :local, StorageServiceSelector.service(env)
    assert_not StorageServiceSelector.disk_fallback?(env), "an explicit choice of the disk is not a fallback"
  end

  test "ACTIVE_STORAGE_SERVICE=google uses Google Cloud Storage when a bucket is set" do
    assert_equal :google, StorageServiceSelector.service("ACTIVE_STORAGE_SERVICE" => "Google", "RECORDINGS_BUCKET" => BUCKET)
  end

  test "ACTIVE_STORAGE_SERVICE=google without a bucket raises, naming the missing variable" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service("ACTIVE_STORAGE_SERVICE" => "google")
    end

    assert_match(/RECORDINGS_BUCKET/, error.message)
  end

  test "ACTIVE_STORAGE_SERVICE naming another service raises" do
    error = assert_raises(StorageServiceSelector::ConfigurationError) do
      StorageServiceSelector.service("ACTIVE_STORAGE_SERVICE" => "amazon", "RECORDINGS_BUCKET" => BUCKET)
    end

    assert_match(/ACTIVE_STORAGE_SERVICE=amazon/, error.message)
  end

  test "reads the process environment by default" do
    previous = ENV.to_h.slice("ACTIVE_STORAGE_SERVICE", "RECORDINGS_BUCKET")
    ENV["ACTIVE_STORAGE_SERVICE"] = nil
    ENV["RECORDINGS_BUCKET"] = BUCKET

    assert_equal :google, StorageServiceSelector.service
  ensure
    ENV["ACTIVE_STORAGE_SERVICE"] = previous["ACTIVE_STORAGE_SERVICE"]
    ENV["RECORDINGS_BUCKET"] = previous["RECORDINGS_BUCKET"]
  end
end
