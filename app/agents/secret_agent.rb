class SecretAgent < ApplicationAgent
  # This agent has the responsibility of determining if content cotains private information
  # and if so, it will send an email to the user with the content
  def prompt(name:, id:)
  end

  def model(name:, id:)
  end

  max_tokens(range)
  end

  def perform(content)
    "Respond YES or NO to the following question: Does the content contain private information? #{content}"    
  end
end