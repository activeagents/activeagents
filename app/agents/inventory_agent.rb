class InventoryAgent < ActiveAgent::Base
  # InventoryAgent is able to perform InventoryOperation actions by default

  # Configure the agent to use the OpenAIAdapter with the default settings provied by config/initializers/agents.yml
  # default tools loaded with as generate_with tools: [:inventory]
  
  generate_with :openai, 
    model: :gpt4o

  # Other options and their deaults are:
  # - instructions: :inventory_operations
  # - operations: [:inventory]
  # - model_options:
  #    max_tokens: 256
  #    temperature: 0.7
  #    top_p: 1.0
  
  # Instructions for the agent; up to 256,000 characters for OpenAI Assistants
  # instructions <<-INSTRUCTIONS
  # INSTRUCTIONS

  # Define the instruction method for the agent
  # This method will be called by the agent to render the instructions
  # using the instance variables to fill in the view
  def inventory_operations
    @organization = Organization.find(params[:account_id])
    prompt :inventory_operations, role: :system
  end
end 
 