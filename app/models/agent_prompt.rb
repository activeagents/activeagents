# frozen_string_literal: true

class AgentPrompt < ApplicationRecord
  belongs_to :agent

  validates :name, presence: true, uniqueness: { scope: [ :agent_id, :version ] }
  validates :content, presence: true

  before_save :compute_content_hash

  scope :latest_versions, -> {
    select("DISTINCT ON (agent_id, name) agent_prompts.*")
      .order(:agent_id, :name, version: :desc)
  }

  scope :by_name, ->(name) { where(name: name) }

  def next_version
    self.class.where(agent_id: agent_id, name: name).maximum(:version).to_i + 1
  end

  def create_new_version(new_content)
    self.class.create!(
      agent: agent,
      name: name,
      content: new_content,
      version: next_version,
      variables: variables
    )
  end

  def render(variable_values = {})
    result = content.dup
    variable_values.each do |key, value|
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  private

  def compute_content_hash
    self.content_hash = Digest::SHA256.hexdigest(content)
  end
end
