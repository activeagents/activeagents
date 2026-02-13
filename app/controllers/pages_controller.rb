# frozen_string_literal: true

class PagesController < ApplicationController
  layout "landing"

  def home
    @sections = load_sections
  end

  def pricing
    @sections = load_sections(:pricing, :services, :platform)
  end

  private

  def load_sections(*names)
    names = [ :hero, :features, :pricing, :services, :platform, :faq ] if names.empty?
    names.each_with_object({}) do |name, hash|
      path = Rails.root.join("app", "content", "landing", "#{name}.md")
      hash[name] = render_markdown(path.read) if path.exist?
    end
  end

  def render_markdown(content)
    markdown = Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(
        hard_wrap: true,
        link_attributes: { target: "_blank" }
      ),
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true
    )
    markdown.render(content).html_safe
  end
end
