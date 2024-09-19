# lib/active_agent/base.rb
require 'abstract_controller'
require 'active_support/all'
require 'action_view'

module ActiveAgent
  class Base < AbstractController::Base
    include Callbacks
    include ActionPrompt
    include QueuedGeneration
    include GenerationProvider
    include Parameterized

    abstract!

    include AbstractController::Rendering

    include AbstractController::Logger
    include AbstractController::Helpers
    include AbstractController::Translation
    include AbstractController::AssetPaths
    include AbstractController::Callbacks
    include AbstractController::Caching

    include ActionView::Layouts

    PROTECTED_IVARS = AbstractController::Rendering::DEFAULT_PROTECTED_INSTANCE_VARIABLES + [:@_action_has_layout]

    # Define class attributes and accessors
    class_attribute :default_params
    class_attribute :provider
    class_attribute :model_name
    class_attribute :default_instructions

    # Define how the agent should generate content
    def self.generate_with(provider, model:, instructions: :instructions)
      self.provider = provider
      self.model_name = model
      self.default_instructions = instructions
    end

    # Handle action methods dynamically
    def self.method_missing(method_name, *args, &block)
      if action_methods.include?(method_name.to_s)
        ActiveAgent::Generation.new(self, method_name, *args)
      elsif public_instance_methods.include?(:prompt)
        ActiveAgent::Generation.new(self, :prompt, *args)
      else
        super
      end
    end

    def self.respond_to_missing?(method_name, include_private = false)
      action_methods.include?(method_name.to_s) || super
    end

    # Collect all action methods defined in the agent class, excluding inherited methods
    def self.action_methods
      @action_methods ||= public_instance_methods(false).map(&:to_s) - base_instance_methods
    end

    # Base instance methods to exclude from action methods
    def self.base_instance_methods
      ActiveAgent::Base.public_instance_methods(false).map(&:to_s)
    end

    # Define the queue name for generate_later
    def self.generate_later_queue_name
      :default
    end

    # Handle exceptions in the agent class
    def self.handle_exception(exception)
      Rails.logger.error "ActiveAgent Error: #{exception.message}"
      # Additional error handling can be implemented here
    end

    # Initialize instance variables
    def initialize
      super()
    end

    # Accessors for params and context
    attr_accessor :message
    attr_reader :content, :params, :context

    # Default prompt action
    def prompt
    end

    # Render the default instructions
    def instructions
      render template: "#{self.class.name.underscore}/instructions", formats: [:text]
    end

    # Generate a response from the provider
    def perform_generation
      provider_instance.generate(self)
    end

    # Initialize the provider instance
    def provider_instance
      @provider_instance ||= GenerationProvider.for(self.class.provider)
    end

    # Handle exceptions
    def handle_exceptions
      yield
    rescue => e
      self.class.handle_exception(e)
    end

    private

    # Store action name and args when processing the action
    def process_action(action, *args)
      @_action_name = action
      @_args = args
      super(action, *args)
    end
  end
end
