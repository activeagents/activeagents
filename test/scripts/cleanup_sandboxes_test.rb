# frozen_string_literal: true

require "test_helper"
require "open3"

# scripts/incus/cleanup-sandboxes.sh against a fake `incus` that answers from
# files: one label per file, and every delete appended to `deleted`.
class CleanupSandboxesTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("scripts/incus/cleanup-sandboxes.sh").to_s

  FAKE_INCUS = <<~'SH'
    #!/bin/bash
    case "$1" in
      list) cat "$FAKE_INCUS/containers" ;;
      config) [[ -f "$FAKE_INCUS/$3.$4" ]] && cat "$FAKE_INCUS/$3.$4" || echo "" ;;
      delete) echo "$3" >> "$FAKE_INCUS/deleted" ;;
    esac
  SH

  setup do
    skip "the reaper needs GNU date" unless system("date -d @0 >/dev/null 2>&1")

    @dir = Pathname(Dir.mktmpdir("cleanup-sandboxes"))
    @bin = @dir.join("bin")
    FileUtils.mkdir_p(@bin)
    @bin.join("incus").write(FAKE_INCUS)
    @bin.join("incus").chmod(0o755)
  end

  teardown do
    FileUtils.rm_rf(@dir) if @dir
  end

  def container(name, **labels)
    @dir.join("containers").open("a") { |file| file.puts(name) }
    labels.each { |key, value| @dir.join("#{name}.user.#{key}").write("#{value}\n") }
  end

  def reap
    env = { "PATH" => "#{@bin}:#{ENV.fetch("PATH")}", "FAKE_INCUS" => @dir.to_s }
    _output, status = Open3.capture2e(env, "bash", SCRIPT)
    assert status.success?
    @dir.join("deleted").file? ? @dir.join("deleted").read.split : []
  end

  test "a container is removed once its session's expiry has passed, and not before" do
    now = Time.current
    container "sandbox-expired", expires_at: (now - 1.minute).utc.iso8601, created_at: (now - 3.hours).utc.iso8601
    container "sandbox-checkout", expires_at: (now + 1.hour).utc.iso8601, created_at: (now - 1.hour).utc.iso8601

    assert_equal [ "sandbox-expired" ], reap
  end

  test "a container without an expiry is removed by age, and one without either label is left alone" do
    now = Time.current
    container "sandbox-old", created_at: (now - 1.hour).utc.iso8601
    container "sandbox-new", created_at: (now - 1.minute).utc.iso8601
    container "sandbox-unlabelled"
    container "sandbox-garbled", expires_at: "not a time"

    assert_equal [ "sandbox-old" ], reap
  end

  test "only sandbox containers are considered" do
    container "app-runtime-builder-1", created_at: (Time.current - 2.hours).utc.iso8601

    assert_empty reap
  end
end
