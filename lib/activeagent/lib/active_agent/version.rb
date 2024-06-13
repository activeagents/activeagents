# frozen_string_literal: true

require_relative "gem_version"

module ActiveAgent
  # Returns the currently loaded version of Active Agent as a +Gem::Version+.
  def self.version
    gem_version
  end
end