# config/initializers/active_agent.rb
ActiveAgent.load_configuration(Rails.root.join('config', 'agents.yml'))
