# frozen_string_literal: true

class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "landing"

  # The same app serves two landers, split by host (the load balancer's URL
  # map has no host rules, so every domain lands here):
  #   - activeagent.dev            -> open-source lander (framework, free gem)
  #   - activeagents.ai / .pro     -> commercial lander (platform, PRO gems)
  # ?site=oss / ?site=commercial force a variant for previewing.
  OSS_HOSTS = %w[activeagent.dev www.activeagent.dev].freeze

  helper_method :oss_site?

  def home
    @sections = load_sections

    render :home_oss if oss_site?
  end

  def pricing
    @sections = load_sections(:pricing, :services, :platform)
  end

  private

  def oss_site?
    return true if params[:site] == "oss"
    return false if params[:site] == "commercial"

    OSS_HOSTS.include?(request.host)
  end

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
