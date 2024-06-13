
ActiveAgent is a framework for building intelligent agents that can interact with a variety of services and APIs. It is designed to be flexible and extensible, allowing developers to easily create new agents that leverage models and stores from various service providers that can be used in a wide range of applications.

## Installation
```ruby
gem install activeagent
```

## Usage
```ruby
require 'activeagent'
```

## Configuration
```ruby
ActiveAgent.configure do |config|
  config.default_service = {
    service: :openai,
    model: :"gpt-3.5-turbo-16k",
  }
  config.default_store = {
    service: :pg,
  }

## Development
After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

ActiveAgent::Base
ActiveAgent::Operation#perform
ActiveAgent::Operation#instructions
ActiveAgent::Operation#prompt
ActiveAgent::Operation#result


ActiveAgent::Service
ActiveAgent::OpenRouter < ActiveAgent::Service
Handle the routing of requests to the appropriate LLM model's service









ActiveAgent::ModelAdapters
ActiveAgent::ModelAdapter
ActiveAgent::Validator < ActiveModel::Validator
ActiveAgent::OperationExecution 
ActiveAgent::OperationExecutionJob < ActiveJob::Base
ActiveAgent::Prompt < ActiveRecord::Base
ActiveAgent::Prompt < ActiveModel::Base



ActiveAgent::Reasoning



ActiveAgent::TernaryOperator





