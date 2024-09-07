# ActiveAgents

ActiveAgents is a Rails application designed to develop and demonstrate the capabilities of Solid Agent and Active Agent, two powerful libraries for leveraging large language models (LLMs) and other AI tools within the Rails ecosystem. This project is part of the activeagent organization.

## Overview

ActiveAgents serves as a comprehensive platform to showcase the integration and usage of Solid Agent and Active Agent. The application provides examples, documentation, and a demo environment to help developers understand how to effectively utilize these libraries in their own Rails applications.

## Repository Structure

- **ActiveAgents (`activeagent/activeagents`)**: The primary Rails application for development and demonstration purposes.
- **Solid Agent (`activeagent/solid_agent`)**: A library for building robust agents with support for multiple LLMs.
- **Active Agent (`activeagent/activeagent`)**: A Rails plugin that simplifies the creation and management of agents, with support for asynchronous operations and generative adapters.

## Key Features

### Solid Agent

- **Multi-LLM Support**: Integrate with various large language models through centralized configuration.
- **Agent Framework**: Define agents with a common interface and implement custom logic for different tasks.
- **Extensible Design**: Easily add new generative adapters to support additional LLMs.

### Active Agent

- **Asynchronous Operations**: Use `operate_later` and `operate_later!` to queue tasks for background processing.
- **Configuration Management**: Load and manage configurations for different LLMs from `config/` directory.
- **Job Integration**: Seamlessly integrate with ActiveJob for scheduling and executing tasks asynchronously.

## Getting Started

### Prerequisites

- Ruby on Rails (version 6.0 or higher)
- PostgreSQL (for database)
- Redis (for background job processing)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/activeagent/activeagents.git
   cd activeagents
   ```

2. **Install dependencies**:
   ```bash
   bundle install
   yarn install
   ```

3. **Set up the database**:
   ```bash
   rails db:setup
   ```

4. **Start the server**:
   ```bash
   rails server
   ```

5. **Visit the application**: Open your browser and navigate to `http://localhost:3000`

### Configuration

Configure the available generative adapters and other settings in `config/application.rb` or `config/initializers/active_agent.rb`. Load specific configurations for each LLM in the `config/` directory (e.g., `chatgpt.yml`, `gemini.yml`).

### Example Usage

Define and use agents in your Rails application as follows:

**BaseAgent Class**
```ruby
class BaseAgent << SolidAgent::
  def operate
    # Define synchronous operation logic here
  end

  def operate_later
    # Queue the operation for background processing
  end

  def operate_later!
    # Queue the operation for background processing with higher priority
  end
end
```

**ContentFilterAgent Class**
```ruby
class ContentFilterAgent < BaseAgent
  def operate
    # Define content filtering logic using LLM here
  end
end
```

**Job Class for Asynchronous Operations**
```ruby
class AgentJob < ApplicationJob
  queue_as :default

  def perform(agent_class, *args)
    agent_class.constantize.new(*args).operate
  end
end
```

## Contributing

We welcome contributions to improve ActiveAgents, Solid Agent, and Active Agent. To contribute, please follow these steps:

1. **Fork the repository**.
2. **Create a new branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Commit your changes**:
   ```bash
   git commit -m 'Add some feature'
   ```
4. **Push to the branch**:
   ```bash
   git push origin feature/your-feature-name
   ```
5. **Create a pull request**.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

For any questions or suggestions, feel free to open an issue or contact us at [contact@activeagent.org](mailto:contact@activeagent.org).

---

Happy coding! 🚀