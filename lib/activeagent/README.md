# Active Agent
Generative AI powered Rails apps

## What is Active Agent?
Active Agent is a framework for interacting with generative AI services. ActiveAgent provides a simple and flexible service adapter interface to support various AI providers.

## How does Active Agent work?
Active Agent provides an interface to define Agents that can load context take prompts then generate content or perform actions. Agents can receive text, image, audio prompts to generate content in the form of text, image, and audio.

### Define Agents
Agents are the core of Active Agent. An agent takes instructions and can perform actions augment responses by providing data used for generation. Agents are defined by a simple Ruby class that inherits from `ActiveAgent::base` located in the `app/agents` directory.

#### Set your Generative AI provider and model
```ruby
class ModerationAgent < ActiveAgent::Base
  generate_with :openai, model: 'gpt-3.5-turbo', instructions: "Determine if this content is appropriate, by returning YES for appropriate or NO for inappropriate. Only respond with one word `YES` or `NO`."


end

class SummarizationAgent < ActiveAgent::Base, instructions: :summarize
  generate_with :openai, model: 'gpt-4o'

  def summarize
    <<-SUMMARIZE_INSTRUCTIONS
      Summarize content in 1-2 sentences.
    SUMMARIZE_INSTRUCTIONS
  end
end
```

### Generate content
Agents generate content by calling the `generate_now` method with a prompt. The `generate_now` method returns a message object that contains the generated content.

```ruby
ModerationAgent.generate_now("Is this content appropriate? #{content}")
```

Agents can also generate content asynchronously by calling the `generate_later` method with a prompt. The `generate_later` method enqueues an Active Job using the GenerationJob.

```ruby
ModerationAgent.generate_later("Is this content appropriate? #{content}")
```

#### Generate content with context
Agents can generate content with context by calling the `generate_now` method with a prompt and context. The context is used to augment the prompt and provide additional information to the generative AI model.

```ruby
ModerationAgent.generate_now("Is this content appropriate? #{content}", content: content, messages: messages )
```

### Action Prompts
Similarly to ActionController and ActionMailer, Active Agent uses Action Prompt both for rendering `instructions` and dynamic prompt views as well as rendering action views. Action Prompt `instructions` in the form of a system message.

### Define instructions and actions
Instructions are the context provided to the agent to generate content. Actions are the methods that the agent can call to perform tasks. Instructions are defined in the agent class and actions are defined in the `app/agents/operations` `config/operations.rb` file.
```ruby
# app/agents/inventory_agent.rb
class InventoryAgent < ActiveAgent::Base
  generate_with :openai, model: 'gpt-4o'

  # Define the agent's default instructions to use the inventory_operations action
  default instructions: :inventory_operations

  def inventory_operations
    @organization = Organization.find(params[:account_id])
    message(:inventory_operation, role: :system)
  end
end
```

### Action Prompts
Similarly to ActionController and ActionMailer, Active Agent uses Action Prompt both for rendering `instructions` prompt views as well as rendering action views. Action Prompt `instructions` in the form of a system message.

```ruby
# app/views/inventory_agent/inventory_operations.text.erb
  INSTRUCTIONS: You are an inventory manager for <%= @organization.name %>. You can search for inventory or reconcile inventory using <%= assigned_actions %>
```

### What are Actions?
Actions are just Ruby methods so they can do anything app can do already. Actions are commonly used retrieve data or interact with external services. The Actions are called when the agent generates an agent message requesting a function call. Actions are defined on the agent class or as part of an operations controller.

### How do Agents call Actions?
Similar to how Rails needs to define routes to requests to controller actions, Active Agent needs to be provided with the Actions and their JSON schema in order to provide the actions usage information to the Agent. The Actions are defined in a similar way to how Rails defines controller actions. 

# app/agents/inventory_agent.rb
```ruby
class InventoryAgent < ActiveAgent::Base
  generate_with :openai, model: 'gpt-4o'

  # Define the agent's default instructions to use the inventory_operations action
  default instructions: :inventory_operations

  def inventory_operations
    @organization = Organization.find(params[:account_id])
    message(:inventory_operation, role: :system)
  end

  def search
    @inventory = Inventory.find(params[:inventory_id])
    # message(:search, role: :assistant, content: @inventory)
  end
end
```

By default the actions will have a basic schema without any additional information. The schema can be customized by defining a JSON schema in the action view. 

```json.erb
{
  type: "function",
  function: {
    name: "inventory_search",
    description: "Inventory search",
    parameters: {  # Format: https://json-schema.org/understanding-json-schema
      type: :object,
    },
  },
}
```

The inventory search tool schema can be customized in `app/views/inventory_agent/search.json.jbuilder`.

```ruby
# app/views/inventory_agent/search.json.jbuilder
json.type "function"
json.function do
  json.name "inventory_search"
  json.description "Search for inventory by name or SKU"
  json.parameters do
    json.type "object"
    json.properties do
      json.query do
        json.type "string"
        json.description "Search query for full-text search by inventory item name or SKU"
      end
    end
    json.required ["query"]
  end
end
```

```json.erb
{
  type: "function",
  function: {
    name: "inventory_search",
    description: "Search for inventory by name or SKU",
    parameters: {  # Format: https://json-schema.org/understanding-json-schema
      type: :object,
      properties: {
        query: {
          type: :string,
          description: "Search query by inventory name or SKU",
        },
      },
      required: ["query"],
    },
  },
}
```

#### Assigning Actions to Agents
Agents will have Actions defined in their class available to them at all times. Optionally Actions are assigned to agents by defining the `available_actions` method in the agent class. The `available_actions` method returns an array of actions JSON that the agent can perform. Available Actions can be overridden to provide a custom list of actions.

```ruby
# app/agents/inventory_agent.rb
class InventoryReportAgent < ActiveAgent::Base
  # generate_with :openai, model: 'gpt-4o', available_actions: InventoryAgent.actions([:search, :report])
  generate_with :openai, model: 'gpt-4o', available_actions: { inventory: [:search, :report] }

  # Define the agent's default instructions to use the inventory_operations actions.
  default instructions: :inventory_operations

  def inventory_operations
    @organization = Organization.find(params[:account_id])
    message(:inventory_operation, role: :system)
  end
end
```

`InventoryOperations.actions([:search])` returns an array of action JSON schemas that the agent can perform. The Agent can then use the action JSON schema to generate a message that requests the action be performed by the Operations controller. The Operations controller then performs the action and returns the result to the Agent in the form of a message with the results in the message's content. 

#### Actions have consequences

The results of actions are rendered in the form of a message, providing additional information as context to augment the content generation. 

#### Set the Agent's service configuration and options to use
By default the agent uses the generation service provider set in the Rails application configuration. 

## Configuration
Active Agent uses a configuration file to define the service provider and model to use for generation. The configuration file is located in the `config/agents.yml` file.

```yaml
default: &default
  model: "gpt-4o"
  temperature: 0.8
  n: 1

openai: &open_ai
  <<: *default
  service: OpenAI
  project: your_project_name
  organization: your_organization
  api_key: <%= Rails.application.credentials.dig(:openai, :api_key) %>

development:
  <<: *open_ai
  model: "gpt-3.5-turbo"
```

The configuration file is loaded into the Rails application configuration and can be accessed using the `Rails.application.config.active_agent` object. The configuration file can be used to set the default service provider and model to use for generation.

```ruby
class Application < Rails::Application
  config.active_agent.generation_provider = :openai
end
```

#### Generation service provider configurations are defined in the `config/generation.yml` file
```yaml
openai:
  access_token: <%= Rails.application.credentials.openai_access_token %>
```
# Options


### How can agents be used?
Agents can be used to perform actions 

### Configuration
Active Agent uses a configuration file to define the service provider and model to use for generation. The configuration file is located in the `config/agents.yml` file.

```yaml
default: &default
  model: "gpt-4o"
  temperature: 0.8
  n: 1

openai: &open_ai
  <<: *default
  service: OpenAI
  project: your_project_name
  organization: your_organization
  api_key: <%= Rails.application.credentials.dig(:openai, :api_key) %>

development:
  <<: *open_ai
  model: "gpt-3.5-turbo"
```
