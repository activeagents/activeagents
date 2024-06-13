require "active_support"
require "active_support/rails"
require "active_agent/version"
require "active_agent/deprecator"
require "global_id"

module ActiveAgent
  extend ActiveSupport::Autoload
  autoload :Service
end