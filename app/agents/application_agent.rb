class ApplicationAgent < ActiveAgent::Base
  RESPONSES_PER_MESSAGE = 1
  
  generate_with :openai, 
    model: 'gpt-4o-mini'
end