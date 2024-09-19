# Complete Project Plan: Developing the ActiveAgent Gem

This comprehensive project plan outlines the step-by-step development of the **ActiveAgent** Gem, incorporating all the necessary features and functionalities. Each step includes detailed issues, proposed solutions, and complete code examples for every file involved. The plan is designed to guide you through the development process, ensuring a successful implementation of the Gem.

---

## Table of Contents

- [Complete Project Plan: Developing the ActiveAgent Gem](#complete-project-plan-developing-the-activeagent-gem)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Project Overview](#project-overview)
  - [Step-by-Step Issues and Pull Requests](#step-by-step-issues-and-pull-requests)
    - [Issue 1: Initialize the Gem Structure](#issue-1-initialize-the-gem-structure)
      - [Steps:](#steps)
      - [Files:](#files)
      - [Code:](#code)
    - [Issue 2: Implement the Base Modules and Classes](#issue-2-implement-the-base-modules-and-classes)
      - [Files:](#files-1)
      - [Code:](#code-1)
    - [Issue 3: Implement the Generation Provider System](#issue-3-implement-the-generation-provider-system)
      - [Files:](#files-2)
      - [Code:](#code-2)
    - [Issue 4: Implement the OpenAI Provider](#issue-4-implement-the-openai-provider)
      - [Files:](#files-3)
      - [Code:](#code-3)
    - [Issue 5: Implement the Agent Base Class](#issue-5-implement-the-agent-base-class)
      - [Modifications to `lib/active_agent/base.rb`:](#modifications-to-libactive_agentbaserb)
    - [Issue 6: Implement Callbacks Module](#issue-6-implement-callbacks-module)
      - [Modifications to `lib/active_agent/callbacks.rb`:](#modifications-to-libactive_agentcallbacksrb)
    - [Issue 7: Implement ActionPrompt Module with Parameterized Actions](#issue-7-implement-actionprompt-module-with-parameterized-actions)
      - [Files:](#files-4)
      - [Code:](#code-4)
    - [Issue 8: Implement the Generation Class Similar to ActionMailer](#issue-8-implement-the-generation-class-similar-to-actionmailer)
      - [Files:](#files-5)
      - [Code:](#code-5)
    - [Issue 9: Implement the Generation Job for Asynchronous Generation](#issue-9-implement-the-generation-job-for-asynchronous-generation)
      - [Files:](#files-6)
      - [Code:](#code-6)
    - [Issue 10: Implement a Sample Agent (`SupportAgent`)](#issue-10-implement-a-sample-agent-supportagent)
      - [Files:](#files-7)
      - [Code:](#code-7)
    - [Issue 11: Implement Models and Controllers for Messages and Chats](#issue-11-implement-models-and-controllers-for-messages-and-chats)
      - [Files:](#files-8)
      - [Code:](#code-8)
    - [Issue 12: Implement Views for Messages and Chats](#issue-12-implement-views-for-messages-and-chats)
      - [Files:](#files-9)
      - [Code:](#code-9)
    - [Issue 13: Finalize and Publish the Gem](#issue-13-finalize-and-publish-the-gem)
      - [Steps:](#steps-1)
  - [Conclusion](#conclusion)

---

## Introduction

The **ActiveAgent** Gem is designed to integrate generative AI capabilities into Ruby on Rails applications seamlessly. It provides a framework for defining agents that can generate content using AI providers like OpenAI's GPT models. The Gem is inspired by Rails components like ActionMailer and aims to provide a familiar and intuitive interface for developers.

---

## Project Overview

The project involves developing the **ActiveAgent** Gem with the following key features:

- **Generation Providers**: A flexible system to integrate different AI providers.
- **Agent Base Class**: A base class for defining agents with customizable behaviors.
- **Parameterized Actions**: Support for passing instance variables from agents to views.
- **Generation and Delivery Mechanism**: Similar to ActionMailer, providing methods like `generate_now` and `generate_later`.
- **Callbacks and Hooks**: Allowing agents to execute code before and after generation.
- **Sample Agent Implementation**: Providing a concrete example of how to use the Gem.
- **Models and Controllers**: For handling messages and chats within a Rails application.
- **Views and Templates**: For rendering messages and agent-generated content.

---

## Step-by-Step Issues and Pull Requests

Below are the detailed issues and pull requests (PRs) needed to develop the Gem. Each issue includes a description, the files involved, and complete code examples.

---

### Issue 1: Initialize the Gem Structure

**Description**: Set up the basic structure of the Gem using Bundler.

**Pull Request**: `Initialize Gem Structure`

#### Steps:

1. Run `bundle gem active_agent` to generate the Gem scaffold.
2. Configure the gemspec file.
3. Set up basic directories and files.

#### Files:

- `active_agent.gemspec`
- `lib/active_agent.rb`
- `lib/active_agent/version.rb`

#### Code:

**File: `active_agent.gemspec`**

```ruby
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "active_agent"
  spec.version       = ActiveAgent::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "Integrate generative AI into Rails applications."
  spec.description   = "ActiveAgent allows you to define agents that generate content using AI providers."
  spec.homepage      = "https://github.com/yourusername/active_agent"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.0"
  spec.add_dependency "activejob", ">= 6.0"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "actionview"
  spec.add_dependency "activesupport"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake"
end
```

**File: `lib/active_agent.rb`**

```ruby
# frozen_string_literal: true

require "active_agent/version"

module ActiveAgent
  class Error < StandardError; end
  # Your code goes here...
end
```

**File: `lib/active_agent/version.rb`**

```ruby
# frozen_string_literal: true

module ActiveAgent
  VERSION = "0.1.0"
end
```

---

### Issue 2: Implement the Base Modules and Classes

**Description**: Set up the base modules and classes required for the Gem.

**Pull Request**: `Implement Base Modules and Classes`

#### Files:

- `lib/active_agent/base.rb`
- `lib/active_agent/callbacks.rb`
- `lib/active_agent/parameterized.rb`

#### Code:

**File: `lib/active_agent/base.rb`**

```ruby
# frozen_string_literal: true

require "active_support/all"
require "action_view"
require "turbo-rails"

module ActiveAgent
  class Base
    include ActiveAgent::Callbacks
    include ActiveAgent::Parameterized
    include ActionView::Helpers
    include Turbo::Streams::StreamName
    include Turbo::Streams::ActionHelper
    include Turbo::FramesHelper

    attr_accessor :content, :context, :params

    class << self
      attr_accessor :provider, :model_name, :default_instructions

      def generate_with(provider, model:, instructions: :instructions)
        @provider = provider
        @model_name = model
        @default_instructions = instructions
      end

      def prompt(content = nil, **context)
        agent = new
        agent.content = content
        agent.context = context
        agent
      end

      def with(params)
        ParameterizedAgent.new(self, params)
      end
    end

    def initialize
      @params = {}
    end

    def instructions
      render_instructions(self.class.default_instructions)
    end

    def available_actions
      (public_methods(false) - Base.public_instance_methods(false)).map(&:to_s) - ["instructions"]
    end

    def action_schema(action_name)
      JSON.parse(render_action(action_name))
    end
  end
end
```

**File: `lib/active_agent/callbacks.rb`**

```ruby
# frozen_string_literal: true

require "active_support/concern"

module ActiveAgent
  module Callbacks
    extend ActiveSupport::Concern

    included do
      include ActiveSupport::Callbacks
      define_callbacks :generate
      define_callbacks :process_action
    end

    module ClassMethods
      def before_generate(*methods)
        set_callback :generate, :before, *methods
      end

      def after_generate(*methods)
        set_callback :generate, :after, *methods
      end

      def around_generate(*methods)
        set_callback :generate, :around, *methods
      end

      def before_action(*filters, &blk)
        set_callback(:process_action, :before, *filters, &blk)
      end

      def after_action(*filters, &blk)
        set_callback(:process_action, :after, *filters, &blk)
      end

      def around_action(*filters, &blk)
        set_callback(:process_action, :around, *filters, &blk)
      end
    end

    def process(action, *args)
      run_callbacks :process_action do
        public_send(action, *args)
      end
    end
  end
end
```

**File: `lib/active_agent/parameterized.rb`**

```ruby
# frozen_string_literal: true

module ActiveAgent
  module Parameterized
    extend ActiveSupport::Concern

    included do
      attr_writer :params

      def params
        @params ||= {}
      end
    end

    module ClassMethods
      def with(params)
        ParameterizedAgent.new(self, params)
      end
    end

    class ParameterizedAgent
      def initialize(agent_class, params)
        @agent_class = agent_class
        @params = params
      end

      def method_missing(method_name, *args, &block)
        if @agent_class.public_instance_methods.include?(method_name)
          agent = @agent_class.new
          agent.params = @params
          agent.process(method_name, *args, &block)
          agent
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @agent_class.public_instance_methods.include?(method_name) || super
      end
    end
  end
end
```

---

### Issue 3: Implement the Generation Provider System

**Description**: Create a flexible system to integrate different AI providers.

**Pull Request**: `Implement Generation Provider System`

#### Files:

- `lib/active_agent/generation_provider.rb`
- `lib/active_agent/generation_provider/base.rb`
- `lib/active_agent/generation_provider/response.rb`

#### Code:

**File: `lib/active_agent/generation_provider.rb`**

```ruby
# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    def self.for(provider_name)
      config = Rails.application.credentials.dig(:generation_providers, provider_name.to_sym)
      raise "Configuration not found for provider: #{provider_name}" unless config

      Base.configure_provider(config)
    end
  end
end
```

**File: `lib/active_agent/generation_provider/base.rb`**

```ruby
# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    class Base
      attr_reader :agent

      def initialize(agent)
        @agent = agent
      end

      def generate(agent, stream: nil)
        raise NotImplementedError, "Subclasses must implement the generate method"
      end

      def self.configure_provider(config)
        require "active_agent/generation_provider/#{config['service'].underscore}_provider"
        ActiveAgent::GenerationProvider.const_get("#{config['service'].camelize}Provider").new(config)
      rescue LoadError
        raise "Missing generation provider for #{config['service'].inspect}"
      end

      def response_class
        ActiveAgent::GenerationProvider::Response
      end
    end
  end
end
```

**File: `lib/active_agent/generation_provider/response.rb`**

```ruby
# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    class Response
      attr_reader :response

      def initialize(response)
        @response = response
      end

      def content
        raise NotImplementedError, "Subclasses must implement the content method"
      end

      def function_call?
        false
      end

      def function_name
        nil
      end

      def function_arguments
        {}
      end
    end
  end
end
```

---

### Issue 4: Implement the OpenAI Provider

**Description**: Implement the OpenAI provider by subclassing the base provider.

**Pull Request**: `Implement OpenAI Provider`

#### Files:

- `lib/active_agent/generation_provider/open_ai_provider.rb`

#### Code:

**File: `lib/active_agent/generation_provider/open_ai_provider.rb`**

```ruby
# frozen_string_literal: true

require "openai"

module ActiveAgent
  module GenerationProvider
    class OpenAIProvider < Base
      def initialize(config)
        @api_key = config["api_key"]
        super(nil)
      end

      def generate(agent, stream: nil)
        client = OpenAI::Client.new(api_key: @api_key)
        parameters = build_parameters(agent)
        if stream
          parameters[:stream] = true
          client.chat(parameters: parameters) do |chunk, bytesize|
            stream.call(chunk, bytesize)
          end
        else
          response = client.chat(parameters: parameters)
          handle_response(response)
        end
      rescue => e
        handle_error(e)
      end

      def response_class
        Response
      end

      private

      def build_parameters(agent)
        {
          model: agent.class.model_name,
          messages: build_messages(agent),
          temperature: 0.7
        }
      end

      def build_messages(agent)
        messages = []
        if agent.instructions.present?
          system_message = { role: "system", content: agent.instructions }
          messages << system_message
        end
        if agent.content.present?
          user_message = { role: "user", content: agent.content }
          messages << user_message
        end
        messages
      end

      def handle_response(response)
        adapter = response_class.new(response)
        agent.process_response(adapter)
      end

      def handle_error(error)
        Rails.logger.error "OpenAIProvider Error: #{error.message}"
        raise error
      end

      class Response < GenerationProvider::Response
        def content
          response.dig("choices", 0, "message", "content")
        end
      end
    end
  end
end
```

---

### Issue 5: Implement the Agent Base Class

**Description**: Implement methods in `ActiveAgent::Base` to utilize the generation providers.

**Pull Request**: `Implement Agent Base Class Methods`

#### Modifications to `lib/active_agent/base.rb`:

```ruby
# Additional methods in ActiveAgent::Base

def generate_now(message = nil, stream: nil, &block)
  @current_message = message if message
  run_callbacks :generate do
    if stream
      provider_instance.generate(self, stream: stream)
    else
      provider_instance.generate(self, stream: method(:default_stream_handler))
    end
  end
ensure
  @current_message = nil
end

def generate_later(options = {})
  if processed?
    raise "You've accessed the message before asking to generate it later."
  else
    self.class.generation_job.set(options).perform_later(
      self.class.name, :perform, args: [@content, @context])
  end
end

def default_stream_handler(chunk, _bytesize)
  adapter = provider_instance.response_class.new(chunk)
  if adapter.content
    @message ||= initialize_message
    @message.content ||= ''
    @message.content += adapter.content
    @message.save!
  end
  after_stream_chunk if respond_to?(:after_stream_chunk)
end

def provider_instance
  @provider_instance ||= GenerationProvider.for(self.class.provider)
end

private

def initialize_message
  Message.new(chat_id: context[:chat_id], role: 'assistant')
end
```

---

### Issue 6: Implement Callbacks Module

**Description**: Ensure that the Callbacks module supports action processing similar to controllers.

**Pull Request**: `Enhance Callbacks Module`

#### Modifications to `lib/active_agent/callbacks.rb`:

Already included in Issue 3.

---

### Issue 7: Implement ActionPrompt Module with Parameterized Actions

**Description**: Allow agents to pass instance variables from their actions to views.

**Pull Request**: `Implement ActionPrompt with Parameterized Actions`

#### Files:

- `lib/active_agent/action_prompt.rb`

#### Code:

**File: `lib/active_agent/action_prompt.rb`**

```ruby
# frozen_string_literal: true

require "action_view"

module ActiveAgent
  module ActionPrompt
    extend ActiveSupport::Concern

    included do
      include ActionView::Rendering
      include Rails.application.routes.url_helpers
      self.view_paths = ["app/views"]
    end

    def render_instructions(action_name = :instructions)
      render_template(action_name, :text)
    end

    def render_action(action_name, format: :html)
      render_template(action_name, format)
    end

    def render_view(view_name, format: :html)
      render_template(view_name, format)
    end

    private

    def render_template(action_name, format)
      lookup_context.formats = [format]
      template = "#{self.class.name.underscore}/#{action_name}"
      assigns = instance_variables.each_with_object({}) do |var, hash|
        hash[var.to_s.delete("@").to_sym] = instance_variable_get(var)
      end
      render template: template, locals: assigns
    end
  end
end
```

---

### Issue 8: Implement the Generation Class Similar to ActionMailer

**Description**: Create a `Generation` class that wraps around the agent generation process, similar to `ActionMailer::MessageDelivery`.

**Pull Request**: `Implement Generation Class`

#### Files:

- `lib/active_agent/generation.rb`

#### Code:

**File: `lib/active_agent/generation.rb`**

```ruby
# frozen_string_literal: true

require "delegate"

module ActiveAgent
  class Generation < Delegator
    def initialize(agent_class, action, *args)
      @agent_class = agent_class
      @action = action
      @args = args
      @processed_agent = nil
      @message = nil
    end
    ruby2_keywords(:initialize)

    def __getobj__
      @message ||= processed_agent.message
    end

    def __setobj__(message)
      @message = message
    end

    def message
      __getobj__
    end

    def processed?
      @processed_agent || @message
    end

    def generate_now
      processed_agent.handle_exceptions do
        processed_agent.run_callbacks(:generate) do
          processed_agent.generate_message
        end
      end
    end

    def generate_later(options = {})
      if processed?
        raise "You've accessed the message before asking to generate it later."
      else
        @agent_class.generation_job.set(options).perform_later(
          @agent_class.name, @action.to_s, args: @args)
      end
    end

    private

    def processed_agent
      @processed_agent ||= @agent_class.new.tap do |agent|
        agent.process @action, *@args
      end
    end
  end
end
```

---

### Issue 9: Implement the Generation Job for Asynchronous Generation

**Description**: Create a job class for handling asynchronous generation.

**Pull Request**: `Implement Generation Job`

#### Files:

- `lib/active_agent/generation_job.rb`

#### Code:

**File: `lib/active_agent/generation_job.rb`**

```ruby
# frozen_string_literal: true

require "active_job"

module ActiveAgent
  class GenerationJob < ActiveJob::Base
    queue_as :default

    def perform(agent_class_name, action, args: [])
      agent_class = agent_class_name.constantize
      agent = agent_class.new
      agent.process(action, *args)
      agent.generate_message
    end
  end
end
```

---

### Issue 10: Implement a Sample Agent (`SupportAgent`)

**Description**: Provide an example agent to demonstrate how to use the Gem.

**Pull Request**: `Implement Sample Agent`

#### Files:

- `app/agents/support_agent.rb`
- `app/views/support_agent/instructions.text.erb`
- `app/views/support_agent/message.html.erb`

#### Code:

**File: `app/agents/support_agent.rb`**

```ruby
# frozen_string_literal: true

class SupportAgent < ActiveAgent::Base
  generate_with :openai, model: 'gpt-3.5-turbo', instructions: :instructions

  before_action do
    @chat = Chat.find(context[:chat_id])
    @user = User.find(context[:user_id])
  end

  def perform(content, context)
    @content = content
    @context = context
  end

  def generate_message
    provider_instance.generate(self)
  end

  private

  def after_generate
    broadcast_message
  end

  def broadcast_message
    broadcast_append_later_to(
      broadcast_stream,
      target: broadcast_target,
      partial: 'support_agent/message',
      locals: { message: @message }
    )
  end

  def broadcast_stream
    "#{dom_id(@chat)}_messages"
  end

  def broadcast_target
    "#{dom_id(@chat)}_messages"
  end
end
```

**File: `app/views/support_agent/instructions.text.erb`**

```erb
You are assisting <%= @user.name %> in the chat titled "<%= @chat.title %>". Provide helpful responses.
```

**File: `app/views/support_agent/message.html.erb`**

```erb
<div id="<%= dom_id(message) %>">
  <% if message.role == 'user' %>
    <div class="user-message">
      <%= message.content %>
    </div>
  <% else %>
    <div class="assistant-message">
      <%= message.content %>
    </div>
  <% end %>
</div>
```

---

### Issue 11: Implement Models and Controllers for Messages and Chats

**Description**: Create the necessary models and controllers.

**Pull Request**: `Implement Models and Controllers`

#### Files:

- `app/models/message.rb`
- `app/models/chat.rb`
- `app/controllers/messages_controller.rb`
- `app/controllers/chats_controller.rb`

#### Code:

**File: `app/models/message.rb`**

```ruby
# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :chat

  enum role: { system: 0, assistant: 1, user: 2 }

  validates :content, presence: true
end
```

**File: `app/models/chat.rb`**

```ruby
# frozen_string_literal: true

class Chat < ApplicationRecord
  has_many :messages, dependent: :destroy
end
```

**File: `app/controllers/messages_controller.rb`**

```ruby
# frozen_string_literal: true

class MessagesController < ApplicationController
  def create
    @chat = Chat.find(params[:chat_id])
    @message = @chat.messages.create(message_params.merge(role: 'user'))

    agent = SupportAgent.with(user_id: current_user.id).prompt(@message.content, chat_id: @chat.id)
    agent.generate_now

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
```

**File: `app/controllers/chats_controller.rb`**

```ruby
# frozen_string_literal: true

class ChatsController < ApplicationController
  def index
    @chats = Chat.all
  end

  def show
    @chat = Chat.find(params[:id])
    @messages = @chat.messages
  end

  def new
    @chat = Chat.new
  end

  def create
    @chat = Chat.new(chat_params)
    if @chat.save
      redirect_to @chat
    else
      render :new
    end
  end

  private

  def chat_params
    params.require(:chat).permit(:title)
  end
end
```

---

### Issue 12: Implement Views for Messages and Chats

**Description**: Create the views for rendering messages and chats.

**Pull Request**: `Implement Views`

#### Files:

- `app/views/messages/_message.html.erb`
- `app/views/messages/_form.html.erb`
- `app/views/messages/create.turbo_stream.erb`
- `app/views/chats/index.html.erb`
- `app/views/chats/show.html.erb`
- `app/views/chats/_form.html.erb`

#### Code:

**File: `app/views/messages/_message.html.erb`**

```erb
<div id="<%= dom_id(message) %>">
  <% if message.user? %>
    <div class="user-message">
      <%= message.content %>
    </div>
  <% else %>
    <div class="assistant-message">
      <%= message.content %>
    </div>
  <% end %>
</div>
```

**File: `app/views/messages/_form.html.erb`**

```erb
<%= form_with(model: [ @chat, Message.new ], data: { turbo_frame: "message_form" }) do |form| %>
  <%= form.text_area :content, placeholder: "Type your message..." %>
  <%= form.submit "Send" %>
<% end %>
```

**File: `app/views/messages/create.turbo_stream.erb`**

```erb
<%= turbo_stream.append "#{dom_id(@chat)}_messages" do %>
  <%= render @message %>
<% end %>
<%= turbo_stream.replace "message_form" do %>
  <%= render 'messages/form', chat: @chat %>
<% end %>
```

**File: `app/views/chats/index.html.erb`**

```erb
<h1>Chats</h1>

<ul>
  <% @chats.each do |chat| %>
    <li><%= link_to chat.title, chat %></li>
  <% end %>
</ul>

<%= link_to 'New Chat', new_chat_path %>
```

**File: `app/views/chats/show.html.erb`**

```erb
<h1><%= @chat.title %></h1>

<div id="<%= dom_id(@chat) %>_messages">
  <% @messages.each do |message| %>
    <%= render 'messages/message', message: message %>
  <% end %>
</div>

<div id="message_form">
  <%= render 'messages/form', chat: @chat %>
</div>
```

**File: `app/views/chats/_form.html.erb`**

```erb
<%= form_with(model: @chat) do |form| %>
  <%= form.label :title %><br>
  <%= form.text_field :title %><br>
  <%= form.submit %>
<% end %>
```

---

### Issue 13: Finalize and Publish the Gem

**Description**: Prepare the Gem for publishing by writing documentation, setting up tests, and publishing to RubyGems.

**Pull Request**: `Finalize and Publish the Gem`

#### Steps:

1. Write comprehensive documentation in the `README.md`.
2. Set up RSpec or Minitest for testing.
3. Write unit tests for all modules and classes.
4. Ensure all tests pass.
5. Update the `gemspec` with metadata.
6. Build the Gem using `gem build active_agent.gemspec`.
7. Push the Gem to RubyGems using `gem push active_agent-0.1.0.gem`.

---

## Conclusion

By following this detailed project plan, you will successfully develop and publish the **ActiveAgent** Gem, providing a powerful tool for integrating generative AI into Ruby on Rails applications. The step-by-step issues and complete code examples ensure a smooth development process, and the inclusion of sample agents and applications demonstrates how to use the Gem effectively.

---

If you have any questions or need further assistance with any of the steps, feel free to ask!