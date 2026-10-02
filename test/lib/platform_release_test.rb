# frozen_string_literal: true

require "test_helper"

class PlatformReleaseTest < ActiveSupport::TestCase
  # A lockfile in the shape Bundler writes, with only the agent gems in it.
  def lockfile(activeagent: "1.8.1", actionagent: "1.8.1", requirement: "= 1.8.1", solid_agent_from_git: false)
    solid_agent_git = <<~LOCK if solid_agent_from_git
      GIT
        remote: https://github.com/activeagents/solid_agent.git
        revision: 41fd2fe2a31e24994baf2ff8017dad7c3795deac
        branch: main
        specs:
          solid_agent (0.1.1)
            activeagent (>= 1.0.0)

    LOCK

    <<~LOCK
      #{solid_agent_git}GEM
        remote: https://rubygems.org/
        specs:
          actionagent (#{actionagent})
            activeagent (>= 1.4, < 2)
            solid_agent (>= 0.1)
          activeagent (#{activeagent})
            activeagents-telemetry (~> 0.1)
          activeagents-telemetry (0.1.0)
      #{"    solid_agent (0.2.0)\n      activeagent (>= 1.0.0)\n" unless solid_agent_from_git}
      PLATFORMS
        ruby

      DEPENDENCIES
        actionagent (#{requirement})
        activeagent (#{requirement})
        #{solid_agent_from_git ? "solid_agent!" : "solid_agent (= 0.2.0)"}

      BUNDLED WITH
         2.7.2
    LOCK
  end

  def release(tag, existing_tags: [], **lock)
    PlatformRelease.new(tag, lockfile: lockfile(**lock), existing_tags: existing_tags)
  end

  test "a tag naming the locked gems releases them, under every alias the first time" do
    release = release("v1.8.1").verify!

    assert_equal "1.8.1", release.version
    assert_equal "1.8.1", release.gems_version
    assert_equal %w[1.8.1 1.8 latest], release.image_tags
    assert release.latest?
    assert_equal({ "activeagent" => "1.8.1", "actionagent" => "1.8.1", "solid_agent" => "0.2.0", "activeagents-telemetry" => "0.1.0" },
                 release.gem_versions)
  end

  test "a platform-only release keeps the gem version and adds it as an alias" do
    release = release("v1.8.1.2", existing_tags: %w[v1.8.1 v1.8.1.1]).verify!

    assert_equal "1.8.1.2", release.version
    assert_equal "1.8.1", release.gems_version
    assert_equal %w[1.8.1.2 1.8.1 1.8 latest], release.image_tags
  end

  test "re-running an older release moves no alias a newer release holds" do
    assert_equal %w[1.8.1.1 1.8.1 1.8], release("v1.8.1.1", existing_tags: %w[v1.8.1 v1.9.0]).image_tags
    assert_equal %w[1.8.1.1], release("v1.8.1.1", existing_tags: %w[v1.8.1.2 v1.8.2 v1.9.0]).image_tags
    assert_not release("v1.8.1.1", existing_tags: %w[v1.9.0]).latest?
  end

  test "versions compare numerically, and a tag is never newer than itself" do
    release = release("v1.10.0", activeagent: "1.10.0", actionagent: "1.10.0", requirement: "= 1.10.0",
                                 existing_tags: %w[v1.9.0 v1.10.0 v1.1.0])

    assert release.latest?
    assert_equal %w[1.10.0 1.10 latest], release.image_tags
  end

  test "a tag naming other gems than the lock runs is refused" do
    error = assert_raises(PlatformRelease::Error) { release("v1.8.2").verify! }

    assert_match "activeagent is locked at 1.8.1, but v1.8.2 names 1.8.2", error.message
    assert_match "actionagent is locked at 1.8.1, but v1.8.2 names 1.8.2", error.message
  end

  test "a lock that floats the pins or takes solid_agent from git is refused" do
    problems = release("v1.8.1", requirement: "~> 1.8.0", solid_agent_from_git: true).problems

    assert_equal 3, problems.size
    assert_match(/\Asolid_agent comes from .*solid_agent\.git.* instead of RubyGems\z/, problems.first)
    assert_includes problems, %(activeagent is required as ~> 1.8.0 in the Gemfile; pin it exactly (gem "activeagent", "1.8.1"))
  end

  test "anything but vX.Y.Z or vX.Y.Z.N is not a release tag" do
    %w[1.8.1 v1.8 v1.8.1-rc1 v1.8.1.1.1 latest].each do |tag|
      assert_raises(PlatformRelease::Error, tag) { release(tag) }
    end
  end

  test "the next tag is the locked gem version, then numbered platform releases on it" do
    Tempfile.create("Gemfile.lock") do |file|
      file.write(lockfile)
      file.flush

      assert_equal "v1.8.1", PlatformRelease.next_tag(lockfile: file.path, existing_tags: %w[v1.0.0 v1.8.0])
      assert_equal "v1.8.1.1", PlatformRelease.next_tag(lockfile: file.path, existing_tags: %w[v1.8.1])
      assert_equal "v1.8.1.3", PlatformRelease.next_tag(lockfile: file.path, existing_tags: %w[v1.8.1 v1.8.1.2 v1.8.1.1])
    end
  end

  test "outputs are the key=value lines GitHub Actions reads" do
    outputs = release("v1.8.1").to_outputs.lines.to_h { |line| line.chomp.split("=", 2) }

    assert_equal "1.8.1 1.8 latest", outputs["image_tags"]
    assert_equal "true", outputs["latest"]
    assert_equal "0.2.0", outputs["solid_agent"]
  end

  test "the repository's own lock can be released under the tag bin/release suggests" do
    tag = PlatformRelease.next_tag(lockfile: Rails.root.join("Gemfile.lock").to_s)

    assert_empty PlatformRelease.load(tag, lockfile: Rails.root.join("Gemfile.lock").to_s).problems
  end
end
