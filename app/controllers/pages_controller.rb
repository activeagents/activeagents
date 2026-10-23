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

  before_action :send_signed_in_visitors_to_their_dashboard, only: :home

  def home
    @sections = load_sections
    @demo_mode = params[:demo_mode].present?

    render :home_oss if oss_site?
  end

  def pricing
    redirect_to plans_path
  end

  # The privacy policy and terms of service. Linked from the footer, the
  # sign-up page and the Google sign-in consent screen, which requires both
  # to exist at these addresses.
  def privacy
  end

  def terms
  end

  private

  # A signed-in person who opens the site's root wants their dashboard, not
  # the pitch. ?site= and ?demo_mode keep the lander reachable for a look.
  def send_signed_in_visitors_to_their_dashboard
    return if params[:site].present? || params[:demo_mode].present?
    return unless authenticated?

    redirect_to Current.user.email_verified? ? dashboard_path : pending_verification_path
  end

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
