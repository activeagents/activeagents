# frozen_string_literal: true

# Used to choose the Active Storage service a production process keeps its
# files in, by name from config/storage.yml.
#
# `ACTIVE_STORAGE_SERVICE` names the service. Left unset, the service is
# `:google` once `RECORDINGS_BUCKET` is set and `:local` before that, so a
# deploy that predates the bucket keeps working on the instance's disk.
#
# config/environments/production.rb requires this file before the autoloaders
# are set up, so it depends on nothing but Ruby.
module StorageServiceSelector
  SERVICE_VARIABLE = "ACTIVE_STORAGE_SERVICE"
  BUCKET_VARIABLE = "RECORDINGS_BUCKET"
  SERVICES = %i[google local].freeze

  class ConfigurationError < StandardError; end

  module_function

  # Returns `:google` or `:local` for the variables in `env`. Raises
  # ConfigurationError when `ACTIVE_STORAGE_SERVICE` names any other service,
  # or names `google` while `RECORDINGS_BUCKET` is blank.
  def service(env = ENV)
    requested = variable(env, SERVICE_VARIABLE)
    bucket = variable(env, BUCKET_VARIABLE)

    if requested.nil?
      return bucket ? :google : :local
    end

    service = requested.downcase.to_sym
    unless SERVICES.include?(service)
      raise ConfigurationError,
        "#{SERVICE_VARIABLE}=#{requested} names no service in config/storage.yml. Use #{SERVICES.join(' or ')}."
    end

    if service == :google && bucket.nil?
      raise ConfigurationError,
        "#{SERVICE_VARIABLE}=google needs #{BUCKET_VARIABLE}, the Google Cloud Storage bucket to keep files in."
    end

    service
  end

  # Returns true when both variables are blank, which puts files on the
  # instance's disk without anyone having chosen it.
  def disk_fallback?(env = ENV)
    variable(env, SERVICE_VARIABLE).nil? && variable(env, BUCKET_VARIABLE).nil?
  end

  # Returns the stripped value of `name` in `env`, or nil when it is blank.
  def variable(env, name)
    value = env[name].to_s.strip
    value unless value.empty?
  end
  private_class_method :variable
end
