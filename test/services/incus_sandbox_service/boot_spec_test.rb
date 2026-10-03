# frozen_string_literal: true

require "test_helper"

class IncusSandboxService::BootSpecTest < ActiveSupport::TestCase
  BootSpec = IncusSandboxService::BootSpec
  SESSION_ID = "3f2a9c1e-0000-4000-8000-000000000000"

  POSTGRES_YML = <<~YAML
    default: &default
      adapter: postgresql
      encoding: unicode
    development:
      <<: *default
      database: shop_development
  YAML

  def lockfile(gems: {}, ruby: "3.3.6")
    specs = { "railties" => "8.0.2" }.merge(gems).map { |name, version| "    #{name} (#{version})\n" }.join
    lock = "GEM\n  remote: https://rubygems.org/\n  specs:\n#{specs}\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  railties\n"
    lock += "\nRUBY VERSION\n   ruby #{ruby}p100\n" if ruby
    lock + "\nBUNDLED WITH\n   2.6.2\n"
  end

  def checkout(**overrides)
    {
      "Gemfile.lock" => lockfile, "config/application.rb" => "module Shop; end\n", "config/database.yml" => POSTGRES_YML
    }.merge(overrides.transform_keys(&:to_s))
  end

  # The shape ActionAgent::SandboxBootSpec.bootstrap builds.
  def bootstrap_spec(**overrides)
    step = ->(name, command, timeout, **extra) { { "name" => name, "command" => command, "timeout" => timeout, **extra.stringify_keys } }
    {
      "kind" => "bootstrap", "apply" => "always", "preflight" => true,
      "steps" => [
        step.call("bundle_install", "bundle install", 900),
        step.call("add_engine", %(bundle add actionagent --version "~> 1.9.0"), 900, unless_locked: "actionagent"),
        step.call("install_framework", "bin/rails generate active_agent:install --skip", 300, unless_locked: "activeagent"),
        step.call("css_build", "bin/rails css:build", 600, if_task: "css:build"),
        step.call("db_prepare", "bin/rails db:prepare", 900)
      ],
      "env" => { "RAILS_ENV" => "development" }, "secrets" => { "STRIPE_TEST_KEY" => "sk_test_abcdefghijkl" },
      "manifest" => { "command" => "bin/rails action_agent:sandbox:manifest", "timeout" => 300 },
      "start" => { "command" => "bin/rails server -b 127.0.0.1 -p $PORT", "timeout" => 300 },
      "start_url" => "/", "keep_on_failure" => true, "timeout" => 1800
    }.merge(overrides.stringify_keys)
  end

  def build(boot_config: nil, files: checkout, **options)
    BootSpec.build(boot_config: boot_config, files: files, session_id: SESSION_ID, repository: "acme/shop", **options)
  end

  test "a checkout without a spec boots as its sandbox.yml says, with the engine's defaults for what it leaves out" do
    sandbox_yml = <<~YAML
      env:
        FEATURE_FLAGS: "off"
      setup:
        - bundle install
        - bin/rails db:setup
      start: bin/rails server -p $PORT
    YAML
    document = build(files: checkout(".activeagents/sandbox.yml": sandbox_yml)).document

    assert_equal "config", document["mode"]
    assert_equal [ [ "setup", "bundle install" ], [ "setup_2", "bin/rails db:setup" ] ], document["steps"].map { |step| step.values_at("name", "command") }
    assert_equal "bin/rails action_agent:sandbox:manifest", document.dig("manifest", "command")
    assert_equal "bin/rails server -p $PORT", document.dig("start", "command")
    assert_equal "off", document.dig("env", "FEATURE_FLAGS")
    assert_not document["keep_on_failure"]
    assert_equal BootSpec::CONFIG_BOOT_TIMEOUT, document["timeout"]
    assert_equal IncusSandboxService::BOOT_SPEC_VERSION, document["version"]
  end

  test "a checkout with no sandbox.yml gets the engine's default setup" do
    document = build.document

    assert_equal [ "bundle install", "bin/rails db:prepare" ], document["steps"].map { |step| step["command"] }
    assert_equal BootSpec::DEFAULT_START, document.dig("start", "command")
  end

  test "a spec for checkouts without the engine leaves one that bundles it to its sandbox.yml" do
    spec = bootstrap_spec(apply: "without_engine")

    assert_equal "spec", build(boot_config: spec).document["mode"]
    assert_equal "config", build(boot_config: spec, files: checkout("Gemfile.lock": lockfile(gems: { "actionagent" => "1.9.0" }))).document["mode"]
    assert_equal "config", build(boot_config: spec, files: checkout(".activeagents/sandbox.yml": "manifest: bin/manifest\n")).document["mode"]
  end

  test "a bootstrap boot resolves the engine's steps against what the checkout locks" do
    boot = build(boot_config: bootstrap_spec, files: checkout("Gemfile.lock": lockfile(gems: { "activeagent" => "1.9.0" })))
    steps = boot.document["steps"].index_by { |step| step["name"] }

    assert_equal "spec", boot.document["mode"]
    assert_equal "bootstrap", boot.document["kind"]
    assert_nil steps["add_engine"]["skip"]
    assert_equal "the checkout already locks activeagent", steps["install_framework"]["skip"]
    assert_equal "css:build", steps["css_build"]["if_task"]
    assert_equal [ 900, 900, 300, 600, 900 ], boot.document["steps"].map { |step| step["timeout"] }
    assert boot.keep_on_failure?
    assert_equal "/", boot.document["start_url"]
    assert_equal "development", boot.document.dig("env", "RAILS_ENV")
  end

  test "secrets are named in the document and travel apart from it" do
    boot = build(boot_config: bootstrap_spec)

    assert_equal [ "STRIPE_TEST_KEY" ], boot.document["secret_names"]
    assert_equal({ "STRIPE_TEST_KEY" => "sk_test_abcdefghijkl" }, boot.secrets)
    assert_not_includes boot.document.to_json, "sk_test_abcdefghijkl"
    assert_empty boot.missing_secrets
  end

  test "a document read back from a container is missing its secrets' values" do
    stored = BootSpec.from_document(JSON.parse(build(boot_config: bootstrap_spec).document.to_json))

    assert_equal [ "STRIPE_TEST_KEY" ], stored.missing_secrets
    assert_empty stored.secrets
  end

  test "the preflight refuses a checkout the engine cannot be installed into, naming the requirement" do
    {
      { "Gemfile.lock": nil } => /no Gemfile\.lock/,
      { "Gemfile.lock": lockfile(ruby: "3.1.4") } => /needs Ruby 3\.1\.4 \(Gemfile\.lock\); the engine needs Ruby 3\.2/,
      { "Gemfile.lock": lockfile(gems: { "railties" => "7.1.3" }) } => /locks railties 7\.1\.3; the engine needs Rails 7\.2/,
      { "config/application.rb": nil } => /no config\/application\.rb at its root/
    }.each do |files, message|
      error = assert_raises(BootSpec::Refused) { build(boot_config: bootstrap_spec, files: checkout(**files)) }
      assert_match message, error.message
      assert_match(/\ASandbox preflight failed: acme\/shop/, error.message)
    end
  end

  test "the preflight reads the Ruby version from .ruby-version when the lock pins none" do
    error = assert_raises(BootSpec::Refused) do
      build(boot_config: bootstrap_spec, files: checkout("Gemfile.lock": lockfile(ruby: nil), ".ruby-version": "3.1.2\n"))
    end

    assert_match(/needs Ruby 3\.1\.2 \(\.ruby-version\)/, error.message)
  end

  test "a preflight that passes is recorded as one of the boot's steps" do
    recorded = build(boot_config: bootstrap_spec, recorded_steps: [ { name: "checkout", status: "succeeded" } ]).document["recorded_steps"]

    assert_equal %w[checkout preflight], recorded.map { |step| step["name"] }
    assert_match(/railties 8\.0\.2/, recorded.last["detail"])
  end

  test "a spec is refused when it would set what the backend owns" do
    [
      [ bootstrap_spec(secrets: { "DATABASE_URL" => "postgres://elsewhere/db" }), /secrets may not set DATABASE_URL/ ],
      [ bootstrap_spec(secrets: { "BUNDLE_GEMFILE" => "/tmp/Gemfile" }), /secrets may not set BUNDLE_GEMFILE/ ],
      [ bootstrap_spec(steps: [ { "name" => "toolchain", "command" => "true" } ]), /"toolchain" is not a step name/ ],
      [ bootstrap_spec(steps: [ { "name" => "a", "command" => "true" }, { "name" => "a", "command" => "true" } ]), /unique/ ],
      [ bootstrap_spec(start_url: "//elsewhere.test/"), /start_url/ ],
      [ bootstrap_spec(kind: "nonsense"), /`kind` must be one of/ ]
    ].each do |spec, message|
      error = assert_raises(BootSpec::Refused) { build(boot_config: spec) }
      assert_match message, error.message
    end
  end

  test "a bootstrap boot gets at least the bootstrap's time, whatever its spec says" do
    assert_equal BootSpec::BOOTSTRAP_TIMEOUT, build(boot_config: bootstrap_spec(timeout: 600)).document["timeout"]
  end

  test "the sandbox gets databases of its own and only the servers they need" do
    toolchain = ->(boot) { boot.document["toolchain"]["services"] }

    postgres = build
    assert_equal "postgresql:///shop_development_sandbox_3f2a9c1e", postgres.document.dig("env", "DATABASE_URL")
    assert_equal [ "postgresql" ], toolchain.call(postgres)
    assert_equal [ IncusSandboxService::RUNTIME_DIR ], postgres.document["directories"], "the manifest's directory, for the app to write"

    sqlite = build(files: checkout("config/database.yml": "development:\n  adapter: sqlite3\n  database: storage/development.sqlite3\n"))
    assert_equal "sqlite3:/workspace/db/development.sqlite3", sqlite.document.dig("env", "DATABASE_URL")
    assert_empty toolchain.call(sqlite)
    assert_equal [ IncusSandboxService::RUNTIME_DIR, BootSpec::DATA_DIR ], sqlite.document["directories"]

    mysql = build(files: checkout("config/database.yml": "development:\n  adapter: trilogy\n  database: shop\n"))
    assert_equal [ "mysql" ], toolchain.call(mysql)
  end

  test "a bundle that uses Redis gets a Redis server unless its env points elsewhere" do
    redis_lock = lockfile(gems: { "sidekiq" => "7.3.0" })
    with_redis = build(files: checkout("Gemfile.lock": redis_lock))

    assert_includes with_redis.document["toolchain"]["services"], "redis"
    assert_equal BootSpec::REDIS_URL, with_redis.document.dig("env", "REDIS_URL")

    elsewhere = build(boot_config: bootstrap_spec(env: { "REDIS_URL" => "redis://cache.internal:6379/1" }), files: checkout("Gemfile.lock": redis_lock))
    assert_not_includes elsewhere.document["toolchain"]["services"], "redis"
    assert_equal "redis://cache.internal:6379/1", elsewhere.document.dig("env", "REDIS_URL")
  end

  test "a database or Redis URL the env points at this container gets its server, whoever set it" do
    toolchain = ->(boot) { boot.document["toolchain"]["services"] }
    sandbox_yml = ->(env) { { ".activeagents/sandbox.yml": { "env" => env }.to_yaml } }

    assert_equal [ "postgresql" ], toolchain.call(build(files: checkout(**sandbox_yml.call("DATABASE_URL" => "postgresql://localhost/shop_sandbox"))))
    assert_equal [ "mysql" ], toolchain.call(build(boot_config: bootstrap_spec(env: { "DATABASE_URL" => "mysql2://127.0.0.1/other" })))
    assert_equal %w[postgresql mysql], toolchain.call(build(files: checkout(**sandbox_yml.call("QUEUE_DATABASE_URL" => "trilogy:///queue"))))
    assert_equal [ "redis" ], toolchain.call(build(files: checkout("config/database.yml": nil, **sandbox_yml.call("REDIS_URL" => "redis://localhost:6379/2"))))
  end

  test "a URL naming another host, or a variable that is not a database's, gets no server" do
    toolchain = ->(env) { build(boot_config: bootstrap_spec(env: env)).document["toolchain"]["services"] }

    assert_empty toolchain.call("DATABASE_URL" => "postgresql://db.internal/shop")
    assert_empty toolchain.call("DATABASE_URL" => "postgresql://db.internal/shop", "ANALYTICS_URL" => "postgresql://localhost/events")
  end

  test "a SQLite database the env places in the data directory gets the directory and no server" do
    document = build(boot_config: bootstrap_spec(env: { "DATABASE_URL" => "sqlite3:#{BootSpec::DATA_DIR}/shop.sqlite3" })).document

    assert_empty document["toolchain"]["services"]
    assert_equal [ IncusSandboxService::RUNTIME_DIR, BootSpec::DATA_DIR ], document["directories"]
  end

  test "the spec's own database variables win over the sandbox's" do
    document = build(boot_config: bootstrap_spec(env: { "DATABASE_URL" => "postgresql:///chosen" })).document

    assert_equal "postgresql:///chosen", document.dig("env", "DATABASE_URL")
  end

  test "the toolchain follows .tool-versions, then the version files, then the lock" do
    assert_equal "3.3.6", build.document.dig("toolchain", "ruby")
    assert_equal "3.4.1", build(files: checkout(".ruby-version": "ruby-3.4.1\n")).document.dig("toolchain", "ruby")

    files = checkout(".tool-versions": "ruby 3.2.5\nnodejs 20.11.1\n", ".ruby-version": "3.4.1", ".nvmrc": "v18.19.0")
    assert_equal [ "3.2.5", "20.11.1" ], build(files: files).document["toolchain"].values_at("ruby", "node")
    assert_equal "18.19.0", build(files: checkout(".nvmrc": "v18.19.0\n")).document.dig("toolchain", "node")
    assert_nil build(files: checkout(".nvmrc": "lts/iron\n")).document.dig("toolchain", "node"), "an alias falls back to the image's Node"
  end

  test "a resumed boot keeps its first decision, its recorded steps, and what the lock held as checked out" do
    first = build(boot_config: bootstrap_spec(apply: "without_engine"), recorded_steps: [ { name: "checkout", status: "succeeded" } ])
    previous = JSON.parse(first.document.to_json)
    # By now add_engine has written the engine into the lock, and the lock
    # alone would say the spec no longer applies.
    resumed = build(boot_config: bootstrap_spec(apply: "without_engine"), previous: previous,
      files: checkout("Gemfile.lock": lockfile(gems: { "actionagent" => "1.9.0", "activeagent" => "1.9.0" })))

    assert_equal "spec", resumed.document["mode"]
    steps = resumed.document["steps"].index_by { |step| step["name"] }
    assert_nil steps["add_engine"]["skip"]
    assert_nil steps["install_framework"]["skip"]
    assert_equal %w[checkout preflight], resumed.document["recorded_steps"].map { |step| step["name"] }, "the preflight is not run again"
  end

  test "the steps a resume may start from" do
    assert_equal %w[toolchain bundle_install add_engine install_framework css_build db_prepare manifest start],
      build(boot_config: bootstrap_spec).resumable_steps
  end
end
