# ActiveAgent 
A framework for developing AI powered Rails application features. ActiveAgent provides a structured interface for generating and retrieving knowledge using Agents, Prompts, and Operatros. Agents are the primary interface for generating and retrieving knowledge. Agents support Instructions, Prompts, and retrieval augmented generation with Tools and ActiveRecord backed Embedded Vector Search for augemented knowledge based Context. Agents can participate in Conversations and Operations.
## Features
### Agents (ActiveAgent)
Agents are the primary interface for generating and retrieving knowledge. Agents support Instructions, Prompts, and retrieval augmented generation with Tools and ActiveRecord backed Embedded Vector Search for augemented knowledge based Context. Agents can participate in Conversations and Operations.
Agents support Instructions, Prompts, and retrieval augmented generation with Tools and ActiveRecord backed Embedded Vector Search for augemented knowledge based Context. Agents can participate in Conversations and Operations. 
Agents have the following attributes:
- `prompts`
- `generation_provider`
- `generate_with` aliases `generation_provider`
### Prompts (ActionPrompt)
Prompts support Instructions, Context, and additional prompting for Agents. Prompts leverage ActionView in a similar fashion as ActionMailer. ActionPrompt provides a structured interface for generating and retrieving knowledge. 
Prompts have the following attributes:
- `name`
- `unique_identifier`
- `instruction`
- `context`
- `prompt_template`
- `additional_instructions`
- `additional_context`
- `additional_prompting`
- `before_prompt`
- `after_prompt`
- `input`
- `output`
- `prompt_executions`
### Tools (ActiveAgent::Tool)
Tools support calling function or retrieving information from GenerationBackends or ActiveRecord backed Embedded Vector Search for providing Agent's with augmented knowledge-based Context. Tools have the following attributes:
- `name`
- `type` (function, file_search, vector_search, etc.)
- `description`
- `function`
  - `name`
  - `description`
  - `parameters` a JSONSchema for parameters
- `authentication`
- `schema` OpenAPI JSON schema
- `available_actions` list of available HTTP interfaces
- 
### Operators (ActionOperator)
#### Operational Operators
ActionOperator orchestrates procedural routable operations using Agents as a backend and Prompts as an interface. ActionOperator has actions that are performed by Agents. ActionOperator actions are capable of rendering with ActionView and redirecting to other ActionOperator actions with an ActionPrompt in a similar fashion to ActionController 
#### Generative UI Responses (ActionView)
Renders UI responses using structured responses from Agents.
## Use Cases 
### Model Validation
Validate a model using a agent, prompt, and instructions.
### Chatbot
Create a chatbot using a agent, prompt, and instructions.
### Content Moderation
Moderate content using a agent, prompt, and instructions.


## Examples
### Agents
- [ ] TravelingAgent
    - [ ] GenerationProvider
        - [ ] Gemini
    - [ ] Tools
        - [ ] Google Hotel
        - [ ] Google Flights
        - [ ] Google Maps
- [ ] SummarizingAgent
- [ ] SocialMediaContentOperation
    - [ ] Agents
        - [ ] SocialMediaContentWriterAgent
        - [ ] SocialMediaContentReviewingAgent
    - [ ] Tasks
        - [ ] SummarizeBlogToTweetThreadTask
        - [ ] SummarizeBlogToLinkedInTask
        - [ ] ContentReviewTask
        - [ ] ContentApprovalTask
- [ ] FilteringAgent
### Operations
- [ ] Operations
    - [ ] Tools
    - [ ] Agents
    - [ ] Tasks
### Prompts
- [ ] Classification
- [ ] Creation
- [ ] Evaluation
- [ ] Extraction
- [ ] Image Generation
- [ ] Question Answering
- [ ] Reasoning
- [ ] Summarization
- [ ] Truthiness
## Roadmap
- [ ] Error
- [ ] Logging
- [ ] Prompting
- [ ] Context
    - [ ] Contextualize
- [ ] Conversation
    - [ ] RealtimeGeneration
- [ ] Operation
    - [ ] BackgroundGeneration
    - [ ] ActionDebrief
- [ ] Knowledge
    - [ ] Intelligence
    - [ ] Retrieval
- [ ] Retrieve
    - [ ] ActiveAgent::RetrievalJob
- [ ] Embed
    - [ ] Vectorize
    - [ ] VectorStorage::Provider
    - [ ] ActiveAgent::EmbeddingJob
- [ ] Generation
    - [ ] GenerationProvider
    - [ ] RealtimeGeneration
    - [ ] BackgroundGeneration
- [ ] Stream
    - [ ] GenerationProvider
    - [ ] ActionCable
    - [ ] ActiveAgent::StreamingJob
- [ ] Broadcast
    - [ ] ActionCable
    - [ ] ActiveAgent::BroadcastingJob
- [ ] ActiveAgent::OperationJob
    - [ ] ActiveJob
- [ ] ActiveAgent::GenerationJob
    - [ ] ActiveJob


### 1. Update the BaseAgent Class

Modify the `BaseAgent` to replace `perform` with `operate`.

```ruby
# app/agents/base_agent.rb
module ActiveAgent
  class BaseAgent
    class_attribute :generator_class

    def self.generate_with(generator_name)
      generator_config = load_generator_config(generator_name)
      self.generator_class = case generator_name
                             when :chatgpt
                               ChatGPTGenerator.new(generator_config)
                             when :gemini
                               GeminiGenerator.new(generator_config)
                             when :claude
                               ClaudeGenerator.new(generator_config)
                             when :llama13b
                               Llama13bGenerator.new(generator_config)
                             else
                               raise ArgumentError, "Unknown generator: #{generator_name}"
                             end
    end

    def self.load_generator_config(generator_name)
      config_file = Rails.root.join("config", "#{generator_name}.yml")
      raise "Configuration file not found: #{config_file}" unless File.exist?(config_file)

      YAML.load_file(config_file).symbolize_keys
    end

    def self.operate_later_queue_name
      :default
    end

    def self.delivery_job
      AgentOperationJob
    end

    attr_accessor :generator, :instructions

    def initialize(generator: nil, instructions: "")
      @generator = generator || self.class.generator_class
      @instructions = instructions
    end

    def operate(*args)
      raise NotImplementedError, "Subclasses must implement an operate method"
    end

    def operate_later(*args)
      enqueue_operation :operate, args
    end

    def operate_later!(options = {}, *args)
      enqueue_operation :operate, options, args
    end

    private

    def enqueue_operation(operation_method, *args)
      self.class.delivery_job.set(args.extract_options!).perform_later(
        self.class.name, operation_method, *args
      )
    end
  end
end
```

### 2. Update the Job Class

Ensure the job class uses the `operate` method.

```ruby
# activeagent/lib/jobs/agent_operation_job.rb
class AgentOperationJob < ActiveJob::Base
  queue_as do
    agent_class = arguments.first.constantize
    agent_class.operate_later_queue_name
  end

  rescue_from StandardError, with: :handle_exception_with_agent_class

  def perform(agent_class, method_name, *args)
    agent_class.constantize.public_send(method_name, *args)
  end

  private

  def agent_class
    if agent = Array(@serialized_arguments).first || Array(arguments).first
      agent.constantize
    end
  end

  def handle_exception_with_agent_class(exception)
    if klass = agent_class
      klass.handle_exception exception
    else
      raise exception
    end
  end
end
```

### 3. Define the Content Filter Agent

Update the `ContentFilterAgent` to use the `operate` method.

```ruby
# app/agents/content_filter_agent.rb
module ActiveAgent
  class ContentFilterAgent < BaseAgent
    generate_with :chatgpt

    def operate(data)
      # Ensure the LLM is loaded and instructions are set
      raise "LLM generator not set" unless generator
      raise "Instructions not set" if instructions.empty?

      # Prepare the prompt with the instructions and data
      prompt = "#{instructions}: #{data}"

      # Call the LLM with the prompt
      response = generator.generate(prompt: prompt)

      # Process the response to ensure it's only 'true' or 'false'
      result = response.strip.downcase
      %w[true false].include?(result) ? result == 'true' : false
    end
  end
end
```

### 4. Example Usage

You can now use the `ContentFilterAgent` with `operate` and `operate_later`.

```ruby
# Example usage
instructions = "Please check if the following content contains any mature content. Respond only with 'true' or 'false'."
agent = ActiveAgent::ContentFilterAgent.new(instructions: instructions)
content = "This is a sample text to check for mature content."

# Synchronously operate
result = agent.operate(content)
puts result ? "Content is NSFW" : "Content is safe"

# Asynchronously operate
agent.operate_later(content)

# Asynchronously operate with options
agent.operate_later!(wait: 1.hour, content)
```

### 5. Configuration Files

Ensure you have configuration files in `config/` for each generative adapter, e.g., `chatgpt.yml`.

```yaml
# config/chatgpt.yml
api_key: "your_chatgpt_api_key"
other_settings: "additional_settings"
```

### Summary

This setup allows you to use the `operate` method instead of `perform`, providing a more cohesive and descriptive interface for ActiveAgent classes. It also enables asynchronous operation using `operate_later` and `operate_later!`, similar to how ActionMailer handles email delivery.

# Round 2 brainstorming results
```ruby
# db/migrate/20230605123456_create_prompts_and_prompt_executions.rb
class CreatePromptsAndPromptExecutions < ActiveRecord::Migration[6.1]
  def change
    create_table :prompts do |t|
      t.string :name
      t.string :unique_identifier
      t.timestamps
    end

    add_index :prompts, [:name, :unique_identifier], unique: true

    create_table :prompt_executions do |t|
      t.references :prompt, foreign_key: true
      t.string :model
      t.timestamps
    end
  end
end

# app/models/prompt.rb
class Prompt < ApplicationRecord
  has_many :prompt_executions
  has_one_attached :instruction
  has_one_attached :context
  has_one_attached :prompt_template
  has_one_attached :additional_instructions
  has_one_attached :additional_context
  has_one_attached :additional_prompting
end

# app/models/prompt_execution.rb
class PromptExecution < ApplicationRecord
  belongs_to :prompt
  has_one_attached :before_prompt
  has_one_attached :after_prompt
  has_one_attached :input
  has_one_attached :output
end

# app/agents/concerns/prompt_loader.rb
module PromptLoader
  extend ActiveSupport::Concern

  included do
    before_action :load_prompt if respond_to?(:before_action)
  end

  def load_prompt
    file_path = Rails.root.join('app', 'agents', 'prompts', prompt_directory, 'prompt.yml')
    prompt_data = YAML.load_file(file_path).deep_symbolize_keys

    unique_identifier = ENV['PROMPT_HASH'] || `git rev-parse HEAD`.strip

    @prompt = Prompt.find_or_create_by(name: prompt_directory, unique_identifier: unique_identifier) do |p|
      p.instruction.attach(io: StringIO.new(prompt_data[:instruction]), filename: 'instruction.txt')
      p.context.attach(io: StringIO.new(prompt_data[:context]), filename: 'context.txt')
      p.prompt_template.attach(io: StringIO.new(prompt_data[:prompt_template]), filename: 'prompt_template.txt')
      p.additional_instructions.attach(io: StringIO.new(prompt_data[:additional_instructions]), filename: 'additional_instructions.txt')
      p.additional_context.attach(io: StringIO.new(prompt_data[:additional_context]), filename: 'additional_context.txt')
      p.additional_prompting.attach(io: StringIO.new(prompt_data[:additional_prompting].to_json), filename: 'additional_prompting.json')
    end
  end

  private

  def prompt_directory
    self.class.name.underscore.gsub('_agent', '')
  end
end

# app/agents/active_agent/base.rb
module ActiveAgent
  class Base < ApplicationJob
    include ContextManagement
    include LLMProvider
    include Broadcasting
    include PromptLoader

    attr_accessor :instructions, :knowledge_files, :tools, :prompt

    def initialize(additional_instructions: nil, additional_context: nil, additional_prompting: {}, **options)
      load_prompt
      @instructions = [@prompt.instruction.download, additional_instructions].compact.join("\n")
      @context = [@prompt.context.download, additional_context].compact.flatten
      @additional_prompting = additional_prompting
      super(options)
    end

    def generate(prompt_input)
      prompt_text = render_prompt(@prompt.prompt_template.download, prompt_input)
      prompt_text = [@additional_prompting[:before_prompt], prompt_text, @additional_prompting[:after_prompt]].compact.join("\n")
      output = llm_provider.generate(prompt_with_context(prompt_text))

      # Record the prompt execution
      prompt_execution = PromptExecution.create(
        prompt: @prompt,
        model: llm_provider.class.name
      )
      prompt_execution.before_prompt.attach(io: StringIO.new(@additional_prompting[:before_prompt]), filename: 'before_prompt.txt') if @additional_prompting[:before_prompt]
      prompt_execution.after_prompt.attach(io: StringIO.new(@additional_prompting[:after_prompt]), filename: 'after_prompt.txt') if @additional_prompting[:after_prompt]
      prompt_execution.input.attach(io: StringIO.new(prompt_input.to_json), filename: 'input.json')
      prompt_execution.output.attach(io: StringIO.new(output), filename: 'output.txt')

      output
    end

    def generate_later(prompt_input)
      GenerateResponseJob.perform_later(self, prompt_input)
    end

    private

    def render_prompt(template, params)
      params.each { |key, value| template.gsub!("{{#{key}}}", value) }
      template
    end

    def preload_embeddings(knowledge_files)
      embeddings = knowledge_files.map do |file|
        content = File.read(file)
        llm_provider.embed(content)
      end
      embeddings
    end
  end
end

# app/agents/chat_agent.rb
class ChatAgent < ActiveAgent::Base
  generate_with OpenAIProvider

  def initialize(additional_instructions: nil, additional_context: nil, additional_prompting: {}, **options)
    super(additional_instructions: additional_instructions, additional_context: additional_context, additional_prompting: additional_prompting, **options)
  end

  def operate(user_message)
    response = generate({ "user_message" => user_message })
    broadcast_generated_content('chat_channel', response)
  end
end

# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  def create
    additional_instructions = "Please provide detailed explanations."
    additional_context = ["The user is a beginner in programming."]
    additional_prompting = { before_prompt: "Here's some context:", after_prompt: "Thank you for your help." }

    agent = ChatAgent.new(
      additional_instructions: additional_instructions,
      additional_context: additional_context,
      additional_prompting: additional_prompting
    )

    user_message = params[:message]
    agent.operate(user_message)
    head :ok
  end
end
```