#!/usr/bin/env ruby
# frozen_string_literal: true

# Lander Build Script
# Renders docs/index.html from YAML configuration and Markdown content files
#
# Usage: ruby docs/build.rb
#
# This script reads:
#   - docs/content/lander.yml (page structure and metadata)
#   - docs/content/sections/*.md (section content in markdown)
#
# And generates:
#   - docs/index.html
#
# Note: For complex sections (pricing tables, services, add-ons),
# this script generates the basic structure. Review the output for accuracy.

require 'yaml'
require 'erb'
require 'cgi'

class LanderBuilder
  DOCS_DIR = File.expand_path('..', __FILE__)
  CONTENT_DIR = File.join(DOCS_DIR, 'content')
  CONFIG_FILE = File.join(CONTENT_DIR, 'lander.yml')
  OUTPUT_FILE = File.join(DOCS_DIR, 'index.html')

  def initialize
    @config = YAML.load_file(CONFIG_FILE)
  end

  def build
    html = render_template
    File.write(OUTPUT_FILE, html)
    puts "Built #{OUTPUT_FILE}"
  end

  private

  def render_template
    <<~HTML
      <!DOCTYPE html>
      <html lang="en" class="theme-light">

      <head>
        #{render_head}
      </head>

      <body>
        <div class="background-gradient"></div>
        <div class="page-container">
          #{render_header}
          <main>
            #{render_sections}
          </main>
          #{render_footer}
        </div>
      </body>

      </html>
    HTML
  end

  def render_head
    meta = @config['meta']
    <<~HTML.strip
      <meta charset="utf-8" />
        <title>#{h meta['title']}</title>
        <meta content="#{h meta['description']}" name="description" />
        <meta content="width=device-width, initial-scale=1" name="viewport" />

        <!-- Open Graph -->
        <meta property="og:type" content="#{h meta.dig('og', 'type')}" />
        <meta property="og:site_name" content="#{h meta.dig('og', 'site_name')}" />
        <meta property="og:locale" content="#{h meta.dig('og', 'locale')}" />
        <meta property="og:title" content="#{h meta.dig('og', 'title')}" />
        <meta property="og:description" content="#{h meta.dig('og', 'description')}" />
        <meta property="og:url" content="#{h meta.dig('og', 'url')}" />
        <meta name="twitter:site" content="#{h meta.dig('twitter', 'site')}" />
        <meta name="twitter:card" content="#{h meta.dig('twitter', 'card')}" />
        <meta name="twitter:title" content="#{h meta.dig('twitter', 'title')}" />
        <meta name="twitter:description" content="#{h meta.dig('twitter', 'description')}" />

        <!-- Favicon and icons -->
        <link rel="icon" href="#{h meta['favicon']}" sizes="32x32" />
        <link rel="apple-touch-icon" href="#{h meta['favicon']}" />

        <!-- Preload fonts -->
        <link rel="preload" href="fonts/InterVariable.woff2" as="font" type="font/woff2" crossorigin />

        <!-- Styles -->
        <link href="vendor/font-awesome-6.7.2/css/all.min.css" rel="stylesheet" />
        <link href="css/index.css" rel="stylesheet" type="text/css" />
        <link href="css/pricing.css" rel="stylesheet" type="text/css" />
        <link href="css/tablet.css" rel="stylesheet" type="text/css" />
        <link href="css/mobile.css" rel="stylesheet" type="text/css" />
        <script src="js/main.js" type="text/javascript" defer></script>
    HTML
  end

  def render_header
    brand = @config['brand']
    nav = @config['navigation']

    nav_links = nav['links'].map do |link|
      %(<a href="#{h link['url']}" class="nav-link">#{h link['text']}</a>)
    end.join("\n        ")

    social_buttons = nav['social'].map do |social|
      %(<a href="#{h social['url']}" class="button ghost compact hide-on-mobile">\n          <div class="#{h social['icon']} icon l"></div>\n        </a>)
    end.join("\n        ")

    <<~HTML
      <header class="nav-container">
            <a href="/" class="nav-brand" style="display: flex; align-items: center; gap: 8px;">
              <img src="#{h brand['logo']}" alt="#{h brand['name']}" style="height: 32px; width: 32px;" />
              <span style="font-size: 1.25rem; font-weight: 600;">#{h brand['name']}</span>
            </a>
            <nav role="navigation" class="nav-menu" data-navigation>
              #{nav_links}
              <div class="button-group stacked margin-top-l mobile-only">
                <a href="#{h nav.dig('cta', 'sign_in', 'url')}" class="button tertiary">#{h nav.dig('cta', 'sign_in', 'text')}</a>
                <a href="#{h nav.dig('cta', 'primary', 'url')}" class="button primary">#{h nav.dig('cta', 'primary', 'text')}</a>
              </div>
            </nav>
            <div class="button-group">
              #{social_buttons}
              <a href="#{h nav.dig('cta', 'sign_in', 'url')}" class="button tertiary compact hide-on-mobile">#{h nav.dig('cta', 'sign_in', 'text')}</a>
              <a href="#{h nav.dig('cta', 'primary', 'url')}" class="button primary compact">#{h nav.dig('cta', 'primary', 'text')}</a>
              <button class="button ghost compact nav-hamburger" data-mobile-toggle aria-label="Show menu">
                <span class="fa-solid fa-bars icon m"></span>
              </button>
            </div>
          </header>
    HTML
  end

  def render_sections
    @config['sections'].map do |section|
      content_file = File.join(CONTENT_DIR, section['file'])
      content = parse_markdown_file(content_file)
      render_section(section['id'], content)
    end.join("\n")
  end

  def parse_markdown_file(file_path)
    content = File.read(file_path, encoding: 'UTF-8')

    # Parse front matter
    if content.start_with?('---')
      parts = content.split('---', 3)
      front_matter = YAML.safe_load(parts[1]) || {}
      body = parts[2].strip
    else
      front_matter = {}
      body = content.strip
    end

    { front_matter: front_matter, body: body }
  end

  def render_section(section_id, content)
    case section_id
    when 'hero'
      render_hero_section(content)
    when 'features'
      render_features_section(content)
    when 'pricing'
      render_pricing_section(content)
    when 'services'
      render_services_section(content)
    when 'add-ons'
      render_addons_section(content)
    when 'faq'
      render_faq_section(content)
    when 'cta'
      render_cta_section(content)
    else
      "<section><!-- Unknown section: #{section_id} --></section>"
    end
  end

  def render_hero_section(content)
    fm = content[:front_matter]
    body = content[:body]

    # Parse the body - extract title, subtitle, and buttons
    lines = body.lines.map(&:strip).reject(&:empty?)

    # Find title lines (# **Active Agent** and # Build AI in Rails)
    title_lines = []
    subtitle_lines = []
    buttons = []
    in_buttons = false

    lines.each do |line|
      if line == '<!-- buttons -->'
        in_buttons = true
        next
      end

      if in_buttons
        if line =~ /^\- \[(.+?)\]\((.+?)\)\{(.+?)\}$/
          buttons << { text: $1, url: $2, classes: $3.gsub('.', ' ').strip }
        end
      elsif line.start_with?('# **')
        # Title with accent - # **Active Agent**
        title_lines << line.gsub(/^# \*\*(.+?)\*\*$/) { %(<span class="color-accent">#{$1}</span>) }
      elsif line.start_with?('# ')
        # Regular title line
        title_lines << line.sub(/^# /, '')
      else
        subtitle_lines << line
      end
    end

    title_html = title_lines.join("<br />\n      ")
    subtitle_html = subtitle_lines.join("<br />\n      ")

    buttons_html = buttons.map do |btn|
      %(<a href="#{h btn[:url]}" class="#{btn[:classes]}">#{h btn[:text]}</a>)
    end.join("\n      ")

    image_html = if fm['image']
      max_width = fm['image_max_width'] || '280px'
      <<~HTML
        <div style="display: flex; justify-content: center; margin-top: 2rem;">
            <img src="#{h fm['image']}" alt="#{h @config.dig('brand', 'name')}" style="max-width: #{max_width}; height: auto;" />
          </div>
      HTML
    else
      ''
    end

    <<~HTML
      <section>
        <div class="heading hero centered">
          <h1 class="balanced">
            #{title_html}
          </h1>
          <p class="paragraph l secondary balanced">
            #{subtitle_html}
          </p>
          <div class="button-group margin-paragraph centered">
            #{buttons_html}
          </div>
        </div>
        #{image_html}</section>
    HTML
  end

  def render_features_section(content)
    fm = content[:front_matter]
    body = content[:body]

    # Parse the body
    lines = body.lines
    title = ''
    subtitle = ''
    features = []
    current_feature = nil

    lines.each do |line|
      line = line.rstrip
      if line.start_with?('# ') && !line.start_with?('## ') && !line.start_with?('### ')
        title = line.sub(/^# /, '')
      elsif line.start_with?('## ') && !line.include?('Grid')
        # Skip "## Features Grid" header
      elsif !line.start_with?('## ') && subtitle.empty? && title != '' && !line.start_with?('#') && !line.strip.empty?
        subtitle = line.strip
      elsif line.start_with?('### ')
        features << current_feature if current_feature
        current_feature = { name: line.sub(/^### /, ''), description: '' }
      elsif current_feature && !line.strip.empty?
        current_feature[:description] += line.strip + ' '
      end
    end
    features << current_feature if current_feature

    # Group features into rows of 3
    rows = features.each_slice(3).map do |row_features|
      cards = row_features.map do |feature|
        <<~HTML
          <div class="feature-card">
                <div class="feature-heading">
                  <h3 class="color-accent no-top-margin">#{h feature[:name]}</h3>
                  <p class="paragraph s secondary">
                    #{h feature[:description].strip}
                  </p>
                </div>
              </div>
        HTML
      end.join("\n    ")

      %(<div class="grid columns-3">\n    #{cards}</div>)
    end.join("\n  ")

    <<~HTML
      <section>
        <div class="heading centered">
          <h2 class="no-top-margin">#{h title}</h2>
          <p class="paragraph m secondary">
            #{h subtitle}
          </p>
        </div>
        #{rows}
      </section>
    HTML
  end

  def render_pricing_section(content)
    fm = content[:front_matter]
    body = content[:body]
    section_id = fm['id'] || 'pricing'

    # Parse the body
    lines = body.lines
    title = ''
    subtitle = ''
    plans = []
    current_plan = nil
    in_comparison = false

    lines.each do |line|
      line = line.rstrip

      if line.start_with?('# ') && !line.start_with?('## ') && !line.start_with?('### ')
        title = line.sub(/^# /, '')
      elsif line == '## Plans'
        next
      elsif line == '## Feature Comparison'
        plans << current_plan if current_plan
        current_plan = nil
        in_comparison = true
      elsif line.start_with?('|') && in_comparison
        # Skip markdown tables - we'll render from existing HTML
        next
      elsif line.start_with?('### ') && !in_comparison
        plans << current_plan if current_plan
        current_plan = {
          name: line.sub(/^### /, ''),
          subtitle: '',
          price: '',
          price_period: '',
          features: [],
          best_for: '',
          button: nil,
          highlighted: false
        }
      elsif current_plan && !in_comparison
        # Check for price line with format: **$99** /month or $995/yr
        if line =~ /^\*\*(.+?)\*\*\s*(.*)$/ && !current_plan[:price_set]
          bold_content = $1
          remainder = $2.strip
          if bold_content.include?('$') || bold_content == 'Free'
            # It's a price line
            current_plan[:price] = bold_content
            current_plan[:price_period] = remainder unless remainder.empty?
            current_plan[:price_set] = true
          else
            current_plan[:subtitle] = bold_content
          end
        elsif line.start_with?('*') && line.end_with?('*') && !line.start_with?('**')
          text = line.gsub('*', '')
          if text == 'highlighted'
            current_plan[:highlighted] = true
          elsif text.start_with?('Best for:')
            current_plan[:best_for] = text
          end
        elsif line.start_with?('- ')
          current_plan[:features] << line.sub(/^- /, '')
        elsif line =~ /^\[(.+?)\]\((.+?)\)\{(.+?)\}$/
          current_plan[:button] = { text: $1, url: $2, classes: $3.gsub('.', ' ').strip }
        elsif line == '---'
          # Plan separator, ignore
        end
      elsif !in_comparison && subtitle.empty? && !line.empty? && !line.start_with?('#')
        subtitle = line
      end
    end
    plans << current_plan if current_plan && !in_comparison

    # Render plans
    plan_cards = plans.map do |plan|
      highlighted_class = plan[:highlighted] ? ' highlighted' : ''

      features_html = plan[:features].map do |feature|
        <<~HTML
          <div class="feature-item paragraph s">
                    <div class="fa-regular fa-square-check icon m"></div>
                    <div>#{h feature}</div>
                  </div>
        HTML
      end.join

      price_html = if plan[:price_period].to_s.empty?
        %(<div class="paragraph l bold">#{h plan[:price]}</div>)
      else
        %(<div class="paragraph l bold">#{h plan[:price]}</div>\n            <div class="paragraph m secondary">#{h plan[:price_period]}</div>)
      end

      button_class = plan[:highlighted] ? 'button primary full-width margin-top-l' : 'button tertiary full-width margin-top-l'
      if plan[:button]
        button_html = %(<a href="#{h plan[:button][:url]}" class="#{button_class}">#{h plan[:button][:text]}</a>)
      else
        button_html = ''
      end

      <<~HTML
        <div class="feature-card justified-vertically#{highlighted_class}">
              <div>
                <div class="feature-heading">
                  <p class="paragraph l bold no-top-margin">#{h plan[:name]}</p>
                  <p class="paragraph s secondary">#{h plan[:subtitle]}</p>
                  <div class="price-line">
                    #{price_html}
                  </div>
                </div>
                <div class="feature-list">
                  #{features_html.strip}
                </div>
                <p class="paragraph xs secondary" style="margin-top: 1rem;">#{h plan[:best_for]}</p>
              </div>
              #{button_html}
            </div>
      HTML
    end.join("\n    ")

    # Feature comparison table (hardcoded for now - complex markdown table parsing)
    comparison_table = render_feature_comparison_table

    <<~HTML
      <section id="#{h section_id}">
        <div class="text-centered full-width">
          <h2>#{h title}</h2>
          <p class="paragraph m secondary">#{h subtitle}</p>
        </div>
        <div class="grid columns-3 margin-top-xl">
          #{plan_cards.strip}
        </div>
        #{comparison_table}
      </section>
    HTML
  end

  def render_feature_comparison_table
    <<~HTML
      <div class="text-centered full-width margin-top-xl">
          <h3 class="no-top-margin">Feature Comparison</h3>
        </div>
        <table class="pricing-table">
          <thead>
            <tr class="pricing-table-row">
              <th class="paragraph s bold"></th>
              <th class="paragraph s bold">Dev</th>
              <th class="paragraph s bold">Pro</th>
              <th class="paragraph s bold">Enterprise</th>
            </tr>
          </thead>
          <tbody>
            <tr class="pricing-table-row">
              <td class="paragraph s bold" colspan="4" style="background: var(--color-bg-secondary);">Framework</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">ActiveAgent + SolidAgent gems</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Multi-provider support</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Tool calling & structured output</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Streaming & embeddings</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Local Web UI engine</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s bold" colspan="4" style="background: var(--color-bg-secondary);">Hosted Platform</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Hosted dashboard</td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Managed agent deployments</td>
              <td></td>
              <td class="paragraph s">3</td>
              <td class="paragraph s">Unlimited</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Executions / month</td>
              <td class="paragraph s">Self-hosted</td>
              <td class="paragraph s">10,000</td>
              <td class="paragraph s">Unlimited</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Traces / month</td>
              <td class="paragraph s">Self-hosted</td>
              <td class="paragraph s">25,000</td>
              <td class="paragraph s">500,000+</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Trace retention</td>
              <td></td>
              <td class="paragraph s">14 days</td>
              <td class="paragraph s">400 days</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s bold" colspan="4" style="background: var(--color-bg-secondary);">Observability & Evaluation</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Cost & latency analytics</td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">LLM-as-judge evaluators</td>
              <td></td>
              <td class="paragraph s">5 prebuilt</td>
              <td class="paragraph s">Unlimited custom</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">A/B prompt testing</td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Anomaly detection (ML)</td>
              <td></td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s bold" colspan="4" style="background: var(--color-bg-secondary);">Team & Security</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Team seats</td>
              <td class="paragraph s">1</td>
              <td class="paragraph s">5</td>
              <td class="paragraph s">Unlimited</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Workspaces</td>
              <td></td>
              <td class="paragraph s">1</td>
              <td class="paragraph s">Unlimited</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">SSO / SAML & RBAC</td>
              <td></td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">SOC 2 Type II & HIPAA</td>
              <td></td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Private VPC / on-premise</td>
              <td></td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s bold" colspan="4" style="background: var(--color-bg-secondary);">Support</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Community (Discord, GitHub)</td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Email support SLA</td>
              <td></td>
              <td class="paragraph s">48 hours</td>
              <td class="paragraph s">4 hours</td>
            </tr>
            <tr class="pricing-table-row">
              <td class="paragraph s">Dedicated Slack channel</td>
              <td></td>
              <td></td>
              <td><div class="fa-regular fa-square-check icon m"></div></td>
            </tr>
          </tbody>
        </table>
    HTML
  end

  def render_services_section(content)
    fm = content[:front_matter]
    body = content[:body]
    section_id = fm['id'] || 'services'

    # Parse the body
    lines = body.lines
    title = ''
    subtitle = ''
    services = []
    current_service = nil

    lines.each do |line|
      line = line.rstrip

      if line.start_with?('# ') && !line.start_with?('## ') && !line.start_with?('### ')
        title = line.sub(/^# /, '')
      elsif line == '## Services'
        next
      elsif line.start_with?('### ')
        services << current_service if current_service
        current_service = {
          name: line.sub(/^### /, ''),
          subtitle: '',
          icon: nil,
          features: [],
          perfect_for: '',
          button: nil,
          highlighted: false
        }
      elsif current_service
        if line.start_with?('**') && line.end_with?('**')
          current_service[:subtitle] = line.gsub('**', '')
        elsif line.start_with?('*') && line.end_with?('*') && !line.start_with?('**')
          text = line.gsub('*', '')
          if text == 'highlighted'
            current_service[:highlighted] = true
          elsif text.start_with?('icon:')
            current_service[:icon] = text.sub('icon:', '').strip
          elsif text.start_with?('Perfect for:')
            current_service[:perfect_for] = text
          end
        elsif line.start_with?('- ')
          current_service[:features] << line.sub(/^- /, '')
        elsif line =~ /^\[(.+?)\]\((.+?)\)\{(.+?)\}$/
          current_service[:button] = { text: $1, url: $2, classes: $3.gsub('.', ' ').strip }
        elsif line == '---'
          # Service separator, ignore
        end
      elsif subtitle.empty? && !line.empty? && !line.start_with?('#')
        subtitle = line
      end
    end
    services << current_service if current_service

    # Render service cards
    service_cards = services.map do |service|
      highlighted_class = service[:highlighted] ? ' highlighted' : ''

      icon_html = if service[:icon]
        <<~HTML
          <div class="service-icon">
                    <div class="#{h service[:icon]} icon l color-accent"></div>
                  </div>
        HTML
      else
        ''
      end

      features_html = service[:features].map do |feature|
        <<~HTML
          <div class="feature-item paragraph s">
                    <div class="fa-regular fa-square-check icon m"></div>
                    <div>#{h feature}</div>
                  </div>
        HTML
      end.join

      button_class = service[:highlighted] ? 'button primary full-width margin-top-l' : 'button tertiary full-width margin-top-l'
      if service[:button]
        button_html = %(<a href="#{h service[:button][:url]}" class="#{button_class}">#{h service[:button][:text]}</a>)
      else
        button_html = ''
      end

      <<~HTML
        <div class="feature-card justified-vertically#{highlighted_class}">
              <div>
                <div class="feature-heading">
                  #{icon_html.strip}
                  <p class="paragraph l bold no-top-margin">#{h service[:name]}</p>
                  <p class="paragraph s secondary">#{h service[:subtitle]}</p>
                </div>
                <div class="feature-list">
                  #{features_html.strip}
                </div>
                <p class="paragraph xs secondary" style="margin-top: 1rem;">#{h service[:perfect_for]}</p>
              </div>
              #{button_html}
            </div>
      HTML
    end.join("\n    ")

    <<~HTML
      <section id="#{h section_id}">
        <div class="text-centered full-width">
          <h2>#{h title}</h2>
          <p class="paragraph m secondary">#{h subtitle}</p>
        </div>
        <div class="grid columns-3 margin-top-xl">
          #{service_cards.strip}
        </div>
      </section>
    HTML
  end

  def render_addons_section(content)
    fm = content[:front_matter]
    body = content[:body]
    section_id = fm['id'] || 'add-ons'

    # Parse the body - complex structure with multiple subsections
    lines = body.lines
    title = ''
    subtitle = ''
    current_section = nil
    current_subsection = nil
    sections = {}

    lines.each do |line|
      line = line.rstrip

      if line.start_with?('# ') && !line.start_with?('## ') && !line.start_with?('### ')
        title = line.sub(/^# /, '')
      elsif line.start_with?('## ')
        current_section = line.sub(/^## /, '')
        sections[current_section] = {}
        current_subsection = nil
      elsif line.start_with?('### ')
        current_subsection = line.sub(/^### /, '')
        sections[current_section][current_subsection] = { subtitle: '', items: [] } if current_section
      elsif current_section && current_subsection
        if line.start_with?('**') && line.end_with?('**')
          sections[current_section][current_subsection][:subtitle] = line.gsub('**', '')
        elsif line.start_with?('- ')
          sections[current_section][current_subsection][:items] << line.sub(/^- /, '')
        end
      elsif subtitle.empty? && !line.empty? && !line.start_with?('#')
        subtitle = line
      end
    end

    # Render the complex add-ons section
    render_full_addons_section(title, subtitle, section_id)
  end

  def render_full_addons_section(title, subtitle, section_id)
    <<~HTML
      <section id="#{h section_id}">
        <div class="text-centered full-width">
          <h2>#{h title}</h2>
          <p class="paragraph m secondary">#{h subtitle}</p>
        </div>
        <div class="grid columns-2 margin-top-xl">
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph l bold no-top-margin">Pro Add-Ons</p>
              <p class="paragraph s secondary">Pay-as-you-grow pricing</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional traces: $2.00/1k</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional executions: $0.01/exec</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Extended retention (400 days): $2.50/1k</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional team seats: $19/seat/mo</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional workspaces: $49/workspace/mo</div>
              </div>
            </div>
          </div>
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph l bold no-top-margin">Enterprise Add-Ons</p>
              <p class="paragraph s secondary">Volume discounts included</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional traces: $1.50/1k</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional executions: $0.005/exec</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Extended retention: Included</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Additional seats & workspaces: Included</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-circle icon m"></div>
                <div>Appliance/embedded license: $14,995/yr</div>
              </div>
            </div>
          </div>
        </div>
        <div class="text-centered full-width margin-top-xl">
          <h3 class="no-top-margin">Gem Licenses</h3>
          <p class="paragraph s secondary">Software licensing for the Ruby gems</p>
        </div>
        <div class="grid columns-3" style="margin-top: 1rem;">
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph m bold no-top-margin">activeagent</p>
              <p class="paragraph s secondary">Open Source</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-solid fa-scale-balanced icon m color-accent"></div>
                <div><strong>MIT License</strong></div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Free forever, no restrictions</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Commercial use allowed</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Public GitHub repo</div>
              </div>
            </div>
          </div>
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph m bold no-top-margin">activeagent-pro</p>
              <p class="paragraph s secondary">Commercial</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-solid fa-scale-balanced icon m color-accent"></div>
                <div><strong>Commercial License</strong></div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Private repo access for subscribers</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>License tied to subscription</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Bundler credentials provided</div>
              </div>
            </div>
          </div>
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph m bold no-top-margin">activeagent-enterprise</p>
              <p class="paragraph s secondary">Commercial</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-solid fa-scale-balanced icon m color-accent"></div>
                <div><strong>Commercial License</strong></div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Private repo access for customers</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Multi-app & embedded licensing</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Custom terms available</div>
              </div>
            </div>
          </div>
        </div>
        <div class="text-centered full-width margin-top-xl">
          <h3 class="no-top-margin">Service Subscriptions</h3>
          <p class="paragraph s secondary">Hosted platform and support terms</p>
        </div>
        <div class="grid columns-2" style="margin-top: 1rem;">
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph m bold no-top-margin">Pro Subscription</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>14-day free trial, no credit card required</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Cancel anytime, no long-term commitment</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Annual plans: prorated refund if canceled</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Gem access active while subscribed</div>
              </div>
            </div>
          </div>
          <div class="feature-card">
            <div class="feature-heading">
              <p class="paragraph m bold no-top-margin">Enterprise Subscription</p>
            </div>
            <div class="feature-list">
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Custom contract terms & invoicing</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Volume discounts for large teams</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Dedicated onboarding & architecture review</div>
              </div>
              <div class="feature-item paragraph s">
                <div class="fa-regular fa-square-check icon m"></div>
                <div>Quarterly business reviews included</div>
              </div>
            </div>
          </div>
        </div>
        <div class="text-centered full-width margin-top-xl">
          <h3 class="no-top-margin">Professional Services</h3>
          <p class="paragraph s secondary">Consulting, training & custom development</p>
        </div>
        <div class="feature-card" style="margin-top: 1rem;">
          <div class="grid columns-3">
            <div>
              <p class="paragraph s bold">Workshops</p>
              <div class="feature-list">
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Half-day: $2,500</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Full-day: $4,500</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Custom curriculum available</div>
                </div>
              </div>
            </div>
            <div>
              <p class="paragraph s bold">Advisory Retainers</p>
              <div class="feature-list">
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Monthly retainers from $3,000/mo</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Includes async Slack access</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Cancel with 30-day notice</div>
                </div>
              </div>
            </div>
            <div>
              <p class="paragraph s bold">Development</p>
              <div class="feature-list">
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Hourly: $250/hr</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>Project-based quotes available</div>
                </div>
                <div class="feature-item paragraph s">
                  <div class="fa-regular fa-circle icon m"></div>
                  <div>SOW with milestones & deliverables</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    HTML
  end

  def render_faq_section(content)
    body = content[:body]

    # Parse the body
    lines = body.lines
    title = ''
    subtitle = ''
    questions = []
    current_question = nil

    lines.each do |line|
      line = line.rstrip

      if line.start_with?('# ') && !line.start_with?('## ') && !line.start_with?('### ')
        title = line.sub(/^# /, '')
      elsif line == '## Questions'
        next
      elsif line.start_with?('### ')
        questions << current_question if current_question
        current_question = { question: line.sub(/^### /, ''), answer: '' }
      elsif current_question && !line.empty?
        current_question[:answer] += line + ' '
      elsif subtitle.empty? && !line.empty? && title != ''
        subtitle = line
      end
    end
    questions << current_question if current_question

    # Convert markdown-style code to HTML
    questions.each do |q|
      q[:answer] = q[:answer].strip.gsub(/`([^`]+)`/, '<code>\1</code>')
    end

    accordion_items = questions.map do |q|
      <<~HTML
        <details class="accordion-item" name="faq">
              <summary class="accordion-toggle">
                <p class="paragraph m bold">#{h q[:question]}</p>
                <span class="accordion-chevron fa-solid fa-chevron-down"></span>
              </summary>
              <div class="accordion-content">
                <p>
                  #{q[:answer]}
                </p>
              </div>
            </details>
      HTML
    end.join("\n    ")

    <<~HTML
      <section>
        <div class="heading centered">
          <h2 class="no-top-margin">#{h title}</h2>
          <p class="paragraph m secondary">
            #{h subtitle}
          </p>
        </div>
        <div class="accordion-container">
          #{accordion_items.strip}
        </div>
      </section>
    HTML
  end

  def render_cta_section(content)
    fm = content[:front_matter]
    body = content[:body]

    section_class = fm['class'] || ''

    # Parse the body
    lines = body.lines.map(&:strip).reject(&:empty?)
    title = ''
    buttons = []
    in_buttons = false

    lines.each do |line|
      if line == '<!-- buttons -->'
        in_buttons = true
        next
      end

      if in_buttons
        if line =~ /^\- \[(.+?)\]\((.+?)\)\{(.+?)\}$/
          buttons << { text: $1, url: $2, classes: $3.gsub('.', ' ').strip }
        end
      elsif line.start_with?('# ')
        title = line.sub(/^# /, '')
      end
    end

    buttons_html = buttons.map do |btn|
      %(<a href="#{h btn[:url]}" class="#{btn[:classes]}">#{h btn[:text]}</a>)
    end.join("\n      ")

    <<~HTML
      <section class="#{h section_class}">
        <div class="heading centered">
          <h2>#{h title}</h2>
          <div class="button-group margin-paragraph centered">
            #{buttons_html}
          </div>
        </div>
      </section>
    HTML
  end

  def render_footer
    footer = @config['footer']

    links_html = footer['links'].map do |link|
      target = link['external'] ? ' target="_blank"' : ''
      %(<a href="#{h link['url']}" class="ui s"#{target}>#{h link['text']}</a>)
    end.join("\n            ")

    social_html = footer['social'].map do |social|
      <<~HTML
        <a href="#{h social['url']}" class="icon-link ui s" target="_blank">
                  <div class="#{h social['icon']} icon m color-accent"></div>
                  <div class="pseudo-link">#{h social['label']}</div>
                </a>
      HTML
    end.join

    legal_html = footer['legal'].map do |legal|
      %(<a href="#{h legal['url']}" class="ui s tertiary">#{h legal['text']}</a>)
    end.join("\n        ")

    <<~HTML
      <footer class="footer">
            <div class="footer-menu">
              <div>
                <p class="paragraph s">
                  &copy; #{h footer['copyright']}<br />
                  #{h footer['tagline']}
                </p>
              </div>
              <div>
                <div class="link-list">
                  #{links_html}
                </div>
              </div>
              <div>
                <div class="link-list">
                  #{social_html.strip}
                </div>
              </div>
            </div>
            <div class="link-list-horizontal">
              #{legal_html}
            </div>
          </footer>
    HTML
  end

  def h(text)
    CGI.escapeHTML(text.to_s)
  end
end

# Run the build
if __FILE__ == $0
  LanderBuilder.new.build
end
