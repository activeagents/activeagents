# frozen_string_literal: true

class IncusSandboxService
  # Used to resolve how one checkout boots into the boot spec that the
  # sandbox-app-runtime image's sandbox-app-boot runs
  # (docker/sandbox/app-runtime). Everything that depends on the repository is
  # decided here, from files read out of the checkout before any of its code
  # runs, the way the engine's local backend decides it:
  #
  #   - whether the engine's boot spec applies: one for checkouts without the
  #     engine leaves a checkout that bundles it to its own sandbox.yml
  #   - the spec's preflight: a Gemfile.lock, Ruby 3.2 and railties 7.2 or
  #     later, and config/application.rb at the repository root
  #   - which steps are skipped because the checkout already locks their gem
  #   - the sandbox's own databases (ActionAgent::LocalSandboxDatabases), the
  #     servers they need, Redis for a bundle that uses it, and the Ruby and
  #     Node versions the checkout pins
  #
  # Without an engine spec, or when it does not apply, the checkout boots as
  # its .activeagents/sandbox.yml says (ActionAgent::LocalSandboxBackend::Config).
  #
  # #document is what the service writes into the container. It names the
  # spec's secrets without their values, which travel only in the boot's exec
  # environment (#secrets).
  class BootSpec
    class Refused < StandardError; end

    USER = "sandbox"
    # The app listens on PORT inside the container; the image forwards
    # LISTEN_PORT on every interface to it, whatever address the start
    # command binds.
    PORT = 3000
    LISTEN_PORT = 8080
    DATA_DIR = "/workspace/db"
    # Installing a Ruby the image lacks compiles it.
    TOOLCHAIN_TIMEOUT = 1200
    # A container installs a bundle from nothing, so a boot from sandbox.yml
    # gets as long as the engine gives a bootstrap.
    CONFIG_BOOT_TIMEOUT = 1800
    BOOTSTRAP_TIMEOUT = 1800
    DEFAULT_STEP_TIMEOUT = 600
    MAX_TIMEOUT = 6 * 3600
    MAX_STEPS = 30
    MAX_COMMAND_LENGTH = 4096
    MINIMUM_RUBY = Gem::Version.new("3.2")
    MINIMUM_RAILTIES = Gem::Version.new("7.2")

    KINDS = %w[bootstrap custom].freeze
    APPLY_MODES = %w[always without_engine].freeze
    STEP_NAME = /\A[a-z][a-z0-9_]{0,39}\z/
    # The engine's own reserved names, and the image's toolchain step.
    RESERVED_STEP_NAMES = %w[checkout preflight setup manifest start server toolchain].freeze
    ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    GEM_NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z/
    TASK_NAME = /\A[A-Za-z0-9_][A-Za-z0-9_:.-]{0,99}\z/
    TOOL_VERSION = /\A\d+(?:\.\d+){0,2}\z/
    # Names the backend sets, or that change how Ruby, Bundler, Node or git
    # load code: a secret is handed to the checkout's code, never its loader.
    REFUSED_SECRET_NAME = /
      \A(?:PORT|DATABASE_URL|RUBYOPT|RUBYLIB|LD_PRELOAD|PATH|NODE_OPTIONS)\z |
      _DATABASE_URL\z | \AACTION_AGENT_SANDBOX_ | \ADYLD_ | \ABUNDLE_ | \AGIT_
    /x
    DEFAULT_MANIFEST = "bin/rails action_agent:sandbox:manifest"
    DEFAULT_START = "bin/rails server -b 127.0.0.1 -p $PORT"
    REDIS_GEMS = %w[redis redis-client sidekiq].freeze
    REDIS_URL = "redis://127.0.0.1:6379/0"
    DATABASE_SERVICES = { "postgresql" => "postgresql", "postgis" => "postgresql", "mysql2" => "mysql", "trilogy" => "mysql" }.freeze

    # What is read from the checkout, relative to its root.
    FILES = %w[
      Gemfile.lock .activeagents/sandbox.yml .ruby-version .tool-versions .node-version .nvmrc
      config/database.yml config/application.rb
    ].freeze

    attr_reader :document, :secrets

    class << self
      # @param boot_config [Hash, nil] the engine's boot spec
      #   (ActionAgent::SandboxBootSpec#to_h), secrets included
      # @param files [Hash{String => String, nil}] FILES as read from the
      #   checkout; nil for one that is not there
      # @param session_id [String]
      # @param repository [String, nil] owner/name, for messages and database names
      # @param recorded_steps [Array<Hash>] the backend's own steps so far
      #   (the checkout), for the boot's progress
      # @param previous [Hash, nil] the document of the boot being resumed:
      #   whether its spec applied, and what its Gemfile.lock locked as checked
      #   out, are kept from it, and the preflight is not run again
      # @raise [Refused] for an invalid spec, a malformed sandbox.yml, or a
      #   checkout the preflight refuses
      def build(boot_config:, files:, session_id:, repository: nil, recorded_steps: [], previous: nil)
        new(boot_config: boot_config, files: files, session_id: session_id, repository: repository,
          recorded_steps: recorded_steps, previous: previous)
      end

      # A document already written into a container, to boot again without
      # a new spec. It carries no secret values (see #missing_secrets).
      def from_document(document)
        allocate.tap { |spec| spec.send(:adopt, document) }
      end
    end

    def initialize(boot_config:, files:, session_id:, repository:, recorded_steps:, previous:)
      @files = files.to_h.transform_keys(&:to_s)
      @session_id = session_id.to_s
      @repository = repository.presence || previous&.dig("facts", "repository")
      @previous = previous
      @recorded_steps = recorded_steps.map { |step| step.to_h.stringify_keys }
      @spec = boot_config && parse_spec(boot_config.to_h.deep_stringify_keys)
      @secrets = @spec ? @spec["secrets"] : {}
      @document = resolve
    end

    def keep_on_failure?
      document["keep_on_failure"] == true
    end

    # The secret names the document carries without values: a document read
    # back from a container, booted again without its spec.
    def missing_secrets
      Array(document["secret_names"]) - secrets.keys
    end

    # The step names a resume may start from.
    def resumable_steps
      [ ("toolchain" if document["toolchain"]), *Array(document["steps"]).map { |step| step["name"] }, "manifest", "start" ].compact
    end

    # How long the boot's exec may take: the toolchain's limit and the boot's,
    # and a margin for the script's own work.
    def exec_timeout
      document["timeout"].to_i + document.dig("toolchain", "timeout").to_i + 120
    end

    private

    def adopt(document)
      @document = document.deep_stringify_keys
      @secrets = {}
    end

    def resolve
      mode = spec_applies? ? "spec" : "config"
      document = mode == "spec" ? spec_boot : config_boot
      databases, notes = database_plan(document["env"].merge(@secrets))
      document["env"] = databases.merge(document["env"])
      services = database_services(databases)
      if (redis_bundle? || services.include?("redis")) && !document["env"].key?("REDIS_URL") && !@secrets.key?("REDIS_URL")
        services << "redis"
        document["env"]["REDIS_URL"] = REDIS_URL
      end

      document.merge(
        "version" => IncusSandboxService::BOOT_SPEC_VERSION,
        "mode" => mode,
        "app_dir" => IncusSandboxService::APP_DIR,
        "manifest_path" => IncusSandboxService::RUNTIME_MANIFEST,
        "user" => USER,
        "port" => PORT,
        "listen_port" => LISTEN_PORT,
        "toolchain" => {
          "ruby" => ruby_version, "node" => node_version, "services" => services.uniq, "timeout" => TOOLCHAIN_TIMEOUT
        },
        "directories" => databases.values.any? { |url| url.start_with?("sqlite3:") } ? [ DATA_DIR ] : [],
        "recorded_steps" => @recorded_steps,
        "facts" => {
          "repository" => @repository, "locked_gems" => locked_gems.to_a.sort, "ruby" => lock_facts["ruby"],
          "railties" => lock_facts.dig("gems", "railties"), "database_notes" => notes
        }
      )
    end

    # --- Which boot -----------------------------------------------------------

    def spec_applies?
      return false if @spec.nil?
      return @previous["mode"] == "spec" if @previous
      return true unless @spec["apply"] == "without_engine"

      lock = @files["Gemfile.lock"]
      return false if lock.nil? || lock.match?(/^ {4}actionagent \(/)

      data = sandbox_yml
      !(data.is_a?(Hash) && data.key?("manifest"))
    end

    def sandbox_yml
      text = @files[".activeagents/sandbox.yml"]
      text && YAML.safe_load(text, aliases: false)
    rescue Psych::Exception
      nil
    end

    def spec_boot
      preflight! if @spec["preflight"] && @previous.nil?
      locked = locked_gems
      steps = @spec["steps"].map do |step|
        gem = step["unless_locked"]
        {
          "name" => step["name"], "command" => step["command"], "timeout" => step["timeout"],
          "skip" => gem && locked.include?(gem) ? "the checkout already locks #{gem}" : nil,
          "if_task" => step["if_task"]
        }
      end
      timeout = @spec["kind"] == "bootstrap" ? [ @spec["timeout"], BOOTSTRAP_TIMEOUT ].max : @spec["timeout"]
      {
        "kind" => @spec["kind"], "steps" => steps, "env" => @spec["env"].dup,
        "secret_names" => (@spec["secret_names"] | @secrets.keys),
        "manifest" => @spec["manifest"], "start" => @spec["start"], "start_url" => @spec["start_url"],
        "keep_on_failure" => @spec["keep_on_failure"], "timeout" => timeout
      }
    end

    def config_boot
      config = with_checkout { |app, _workspace| ActionAgent::LocalSandboxBackend::Config.load(app) }
      steps = config.setup.each_with_index.map do |command, index|
        { "name" => index.zero? ? "setup" : "setup_#{index + 1}", "command" => command, "timeout" => nil, "skip" => nil, "if_task" => nil }
      end
      {
        "kind" => nil, "steps" => steps, "env" => config.env.dup, "secret_names" => [],
        "manifest" => { "command" => config.manifest, "timeout" => nil },
        "start" => { "command" => config.start, "timeout" => nil },
        "start_url" => nil, "keep_on_failure" => false, "timeout" => CONFIG_BOOT_TIMEOUT
      }
    rescue ActionAgent::LocalSandboxBackend::Error => e
      raise Refused, e.message
    end

    # --- Preflight ------------------------------------------------------------

    def preflight!
      repository = @repository.presence || "The checkout"
      refuse = ->(problem) { raise Refused, "Sandbox preflight failed: #{problem}" }
      started = Time.current

      refuse.call("#{repository} has no Gemfile.lock at its root: a bootstrap boot needs a bundled Rails app") if @files["Gemfile.lock"].nil?
      ruby, source = lock_facts["ruby"] ? [ lock_facts["ruby"], "Gemfile.lock" ] : [ version_file(".ruby-version"), ".ruby-version" ]
      railties = lock_facts.dig("gems", "railties")
      if ruby && below?(ruby, MINIMUM_RUBY)
        refuse.call("#{repository} needs Ruby #{ruby} (#{source}); the engine needs Ruby #{MINIMUM_RUBY} or later")
      end
      refuse.call("#{repository}'s Gemfile.lock locks no railties: a bootstrap boot needs a Rails app") if railties.nil?
      if below?(railties, MINIMUM_RAILTIES)
        refuse.call("#{repository} locks railties #{railties}; the engine needs Rails #{MINIMUM_RAILTIES} or later")
      end
      if @files["config/application.rb"].nil?
        refuse.call("#{repository} has no config/application.rb at its root: a bootstrap boot needs the Rails app at the repository root")
      end

      finished = Time.current
      @recorded_steps << {
        "name" => "preflight", "status" => "succeeded", "started_at" => started.iso8601(3), "finished_at" => finished.iso8601(3),
        "duration_ms" => ((finished - started) * 1000).round,
        "detail" => "Ruby #{ruby || "unpinned"}, railties #{railties}, actionagent #{lock_facts.dig("gems", "actionagent") || "not locked"}"
      }
    end

    # What the checkout's Gemfile.lock locks, read with Bundler's parser:
    # { "ruby" => "3.3.6" or nil, "gems" => { name => version } }.
    def lock_facts
      @lock_facts ||=
        if (lock = @files["Gemfile.lock"])
          parser = ::Bundler::LockfileParser.new(lock)
          { "ruby" => parser.ruby_version.to_s[/\d+\.\d+(?:\.\d+)?/],
            "gems" => parser.specs.each_with_object({}) { |spec, gems| gems[spec.name] ||= spec.version.to_s } }
        else
          { "ruby" => nil, "gems" => {} }
        end
    rescue StandardError => e
      raise Refused, "Sandbox preflight failed: the checkout's Gemfile.lock could not be read (#{e.message.lines.first.to_s.strip.truncate(200)})"
    end

    # The gems the lock held as checked out, before any step changed it.
    def locked_gems
      @previous ? Array(@previous.dig("facts", "locked_gems")).to_set : lock_facts["gems"].keys.to_set
    end

    def redis_bundle?
      REDIS_GEMS.any? { |gem| locked_gems.include?(gem) }
    end

    def below?(version, minimum)
      Gem::Version.correct?(version) && Gem::Version.new(version) < minimum
    end

    # --- Toolchain ------------------------------------------------------------

    # .tool-versions, then .ruby-version, then the lock's RUBY VERSION; nil
    # for the image's default.
    def ruby_version
      tool_version("ruby") || version_file(".ruby-version") || lock_facts["ruby"]
    end

    def node_version
      tool_version("nodejs") || tool_version("node") || version_file(".node-version") || version_file(".nvmrc")
    end

    def tool_version(tool)
      line = @files[".tool-versions"].to_s.lines.find { |entry| entry.split.first == tool }
      normalize_version(line&.split&.second)
    end

    def version_file(path)
      normalize_version(@files[path].to_s.lines.first)
    end

    # "ruby-3.3.6" and "v20.11.1" as 3.3.6 and 20.11.1. Anything else (an
    # alias such as lts/iron, a range) is nil, and the image's default is used.
    def normalize_version(value)
      version = value.to_s.strip.delete_prefix("ruby-").delete_prefix("v")
      version if TOOL_VERSION.match?(version)
    end

    # --- Databases ------------------------------------------------------------

    # ActionAgent::LocalSandboxDatabases decides the variables from the
    # checkout's config/database.yml, laid out with the files read from the
    # container. A SQLite database it places in its workspace goes under
    # DATA_DIR in the container instead.
    def database_plan(overrides)
      with_checkout do |app, workspace|
        plan = ActionAgent::LocalSandboxDatabases.plan(
          app: app, workspace: workspace, session_id: @session_id, overrides: overrides,
          fallback_name: @repository.to_s.split("/").last
        )
        env = plan.env.transform_values do |url|
          url.start_with?("sqlite3:") ? "sqlite3:#{DATA_DIR}/#{File.basename(url)}" : url
        end
        [ env, plan.notes ]
      end
    rescue ArgumentError => e
      raise Refused, "Sandbox configuration failed: #{e.message}"
    end

    def database_services(env)
      env.values.filter_map { |url| DATABASE_SERVICES[url[/\A([a-z0-9]+):/, 1]] }.uniq
    end

    # Yields an app directory holding the files read from the checkout, and
    # a scratch workspace beside it.
    def with_checkout
      Dir.mktmpdir("incus-checkout") do |dir|
        app = Pathname(dir).join("app")
        FILES.each do |path|
          next if (content = @files[path]).nil?

          file = app.join(path)
          FileUtils.mkdir_p(file.dirname)
          file.binwrite(content)
        end
        FileUtils.mkdir_p(app)
        yield app, Pathname(dir).join("workspace")
      end
    end

    # --- The engine's spec ----------------------------------------------------

    def parse_spec(data)
      kind = one_of(data.fetch("kind", "custom"), KINDS, "kind")
      secrets = parse_env(data["secrets"], "secrets")
      refused = secrets.keys.grep(REFUSED_SECRET_NAME)
      invalid!("secrets may not set #{refused.join(", ")}") if refused.any?

      {
        "kind" => kind,
        "apply" => one_of(data.fetch("apply", "always"), APPLY_MODES, "apply"),
        "preflight" => data["preflight"] == true,
        "steps" => parse_steps(data["steps"]),
        "env" => parse_env(data["env"], "env"),
        "secrets" => secrets,
        "secret_names" => Array(data["secret_names"]).map(&:to_s).select { |name| ENV_NAME.match?(name) },
        "manifest" => parse_command(data["manifest"], "manifest", DEFAULT_MANIFEST),
        "start" => parse_command(data["start"], "start", DEFAULT_START),
        "start_url" => parse_start_url(data.fetch("start_url", "/")),
        "keep_on_failure" => data["keep_on_failure"] == true,
        "timeout" => parse_timeout(data.fetch("timeout", kind == "bootstrap" ? BOOTSTRAP_TIMEOUT : DEFAULT_STEP_TIMEOUT), "timeout")
      }
    end

    def parse_steps(value)
      return [] if value.nil?
      invalid!("`steps` must be a list of at most #{MAX_STEPS} steps") unless value.is_a?(Array) && value.size <= MAX_STEPS

      steps = value.map do |entry|
        invalid!("each step must be a mapping") unless entry.is_a?(Hash)
        name = entry["name"].to_s
        unless STEP_NAME.match?(name) && !RESERVED_STEP_NAMES.include?(name)
          invalid!("#{entry["name"].inspect} is not a step name (lowercase, digits and _; not #{RESERVED_STEP_NAMES.join(", ")})")
        end
        if entry.key?("unless_locked") && !GEM_NAME.match?(entry["unless_locked"].to_s)
          invalid!("step #{name}'s unless_locked must name a gem")
        end
        invalid!("step #{name}'s if_task must name a Rake task") if entry.key?("if_task") && !TASK_NAME.match?(entry["if_task"].to_s)

        {
          "name" => name, "command" => command!(entry["command"], "step #{name}"),
          "timeout" => parse_timeout(entry.fetch("timeout", DEFAULT_STEP_TIMEOUT), "step #{name}'s timeout"),
          "unless_locked" => entry["unless_locked"]&.to_s, "if_task" => entry["if_task"]&.to_s
        }
      end
      duplicate = steps.map { |step| step["name"] }.tally.find { |_name, count| count > 1 }&.first
      invalid!("step names must be unique (#{duplicate} is not)") if duplicate
      steps
    end

    def parse_command(value, key, default)
      return { "command" => default, "timeout" => DEFAULT_STEP_TIMEOUT } if value.nil?

      value = { "command" => value } if value.is_a?(String)
      invalid!("`#{key}` must be a command") unless value.is_a?(Hash)

      { "command" => command!(value["command"], key),
        "timeout" => parse_timeout(value.fetch("timeout", DEFAULT_STEP_TIMEOUT), "#{key}'s timeout") }
    end

    def command!(value, what)
      unless value.is_a?(String) && value.strip.present? && value.length <= MAX_COMMAND_LENGTH && !value.include?("\0")
        invalid!("#{what} needs a command (a string of at most #{MAX_COMMAND_LENGTH} characters)")
      end

      value
    end

    def parse_timeout(value, what)
      seconds = Integer(value, exception: false) if value.is_a?(Integer) || value.is_a?(String)
      invalid!("#{what} must be a number of seconds from 1 to #{MAX_TIMEOUT}") unless seconds&.between?(1, MAX_TIMEOUT)

      seconds
    end

    def parse_env(value, key)
      return {} if value.nil?
      invalid!("`#{key}` must map variable names to strings") unless value.is_a?(Hash)

      value.to_h do |name, setting|
        scalar = setting.is_a?(String) || setting.is_a?(Numeric) || setting == true || setting == false
        unless scalar && ENV_NAME.match?(name.to_s) && !setting.to_s.include?("\0")
          invalid!("`#{key}` must map variable names to strings (#{name.inspect} does not)")
        end

        [ name.to_s, setting.to_s ]
      end
    end

    def parse_start_url(value)
      return nil if value.nil?

      url = value.to_s
      unless url.start_with?("/") && !url.start_with?("//") && url.length <= 2048 && url.match?(/\A[[:graph:]]+\z/)
        invalid!("`start_url` must be a path on the app, such as /")
      end
      url
    end

    def one_of(value, allowed, key)
      value = value.to_s
      invalid!("`#{key}` must be one of #{allowed.join(", ")}, not #{value.inspect}") unless allowed.include?(value)

      value
    end

    def invalid!(problem)
      raise Refused, "Sandbox boot spec is invalid: #{problem}"
    end
  end
end
