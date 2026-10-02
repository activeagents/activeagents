# frozen_string_literal: true

require "bundler"

# What a platform release tag means, checked against the bundle it ships.
#
# The platform is versioned after the agent gems it runs. v1.8.1 is this app
# on activeagent and actionagent 1.8.1, and v1.8.1.1, v1.8.1.2 and so on are
# platform-only releases on that same pair. A tag naming a version the lock
# does not run is refused, and so is a lock that takes an agent gem from git
# or a path: an image published under a version has to rebuild from RubyGems
# alone.
#
# bin/release is the command-line front, and .github/workflows/release.yml
# runs it before building anything.
class PlatformRelease
  Error = Class.new(StandardError)

  TAG = /\Av(?<gems>\d+\.\d+\.\d+)(?:\.(?<patch>\d+))?\z/

  # Pinned exactly in the Gemfile, at the version the tag names.
  PINNED_GEMS = %w[activeagent actionagent].freeze

  # Resolved from RubyGems: the pinned pair and the agent gems they bring.
  RELEASED_GEMS = (PINNED_GEMS + %w[solid_agent activeagents-telemetry]).freeze

  attr_reader :tag, :version, :gems_version

  def self.load(tag, lockfile: "Gemfile.lock", existing_tags: [])
    new(tag, lockfile: File.read(lockfile), existing_tags: existing_tags)
  end

  # The tag the given lock should be released as next: v<activeagent> the
  # first time, then v<activeagent>.1, .2 and so on for platform-only
  # releases on the same gems.
  def self.next_tag(lockfile: "Gemfile.lock", existing_tags: [])
    lock = Bundler::LockfileParser.new(File.read(lockfile))
    gems = lock.specs.find { |spec| spec.name == "activeagent" }&.version&.to_s
    raise Error, "activeagent is not in #{lockfile}" unless gems

    base = "v#{gems}"
    return base unless existing_tags.include?(base)

    patches = existing_tags.filter_map { |existing| existing[/\A#{Regexp.escape(base)}\.(\d+)\z/, 1]&.to_i }
    "#{base}.#{(patches.max || 0) + 1}"
  end

  def initialize(tag, lockfile:, existing_tags: [])
    match = TAG.match(tag.to_s)
    unless match
      raise Error, "#{tag.inspect} is not a release tag. Use vX.Y.Z for the agent gems at X.Y.Z, " \
                   "or vX.Y.Z.N for a platform-only release on them."
    end

    @tag = tag.to_s
    @version = @tag.delete_prefix("v")
    @gems_version = match[:gems]

    lock = Bundler::LockfileParser.new(lockfile)
    @specs = lock.specs.group_by(&:name)
    @dependencies = lock.dependencies

    @existing = existing_tags.filter_map do |existing|
      Gem::Version.new(existing.delete_prefix("v")) if TAG.match?(existing) && existing != @tag
    end
  end

  # Every reason this lock cannot be released under this tag.
  def problems
    released = RELEASED_GEMS.filter_map do |name|
      spec = spec(name)
      next "#{name} is not in Gemfile.lock" unless spec
      next if spec.source.is_a?(Bundler::Source::Rubygems)

      "#{name} comes from #{spec.source} instead of RubyGems"
    end

    pinned = PINNED_GEMS.filter_map do |name|
      requirement = @dependencies[name]&.requirement
      locked = spec(name)&.version&.to_s

      if requirement.nil? || !requirement.exact?
        "#{name} is required as #{requirement || "nothing"} in the Gemfile; pin it exactly (gem \"#{name}\", \"#{gems_version}\")"
      elsif locked && locked != gems_version
        "#{name} is locked at #{locked}, but #{tag} names #{gems_version}"
      end
    end

    released + pinned
  end

  def verify!
    list = problems
    return self if list.empty?

    raise Error, "#{tag} cannot be released from this lock:\n" + list.map { |problem| "  - #{problem}" }.join("\n")
  end

  def gem_versions
    RELEASED_GEMS.to_h { |name| [ name, spec(name)&.version&.to_s ] }
  end

  # Whether no other release is newer: only then does `latest` move, and only
  # then does the release deploy to production.
  def latest?
    newest_in?(nil)
  end

  # The tags this release's image is published under: its full version
  # always, and each shorter alias only while this is the newest release in
  # that alias's line, so re-running an old tag never moves an alias back.
  def image_tags
    minor = gems_version.split(".").first(2).join(".")

    tags = [ version ]
    tags << gems_version if version != gems_version && newest_in?(gems_version)
    tags << minor if newest_in?(minor)
    tags << "latest" if latest?
    tags
  end

  # key=value lines, the format GitHub Actions reads from $GITHUB_OUTPUT.
  def to_outputs
    {
      "tag" => tag,
      "version" => version,
      "gems_version" => gems_version,
      "image_tags" => image_tags.join(" "),
      "latest" => latest?,
      "activeagent" => gem_versions["activeagent"],
      "actionagent" => gem_versions["actionagent"],
      "solid_agent" => gem_versions["solid_agent"],
      "activeagents_telemetry" => gem_versions["activeagents-telemetry"]
    }.map { |key, value| "#{key}=#{value}" }.join("\n")
  end

  private
    def spec(name)
      @specs[name]&.first
    end

    def newest_in?(line)
      current = Gem::Version.new(version)
      @existing.none? do |other|
        other > current && (line.nil? || other.to_s == line || other.to_s.start_with?("#{line}."))
      end
    end
end
