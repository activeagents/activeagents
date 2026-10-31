module ApplicationHelper
  CURRENCY_SYMBOLS = { "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥", "CAD" => "CA$", "AUD" => "A$" }.freeze

  STATUS_TONES = {
    "active" => "success", "completed" => "success", "saved" => "success",
    "running" => "info", "queued" => "info", "new" => "accent",
    "paused" => "muted", "dismissed" => "muted", "failed" => "error"
  }.freeze

  STATUS_LABELS = {
    "active" => "Active", "paused" => "Paused",
    "queued" => "Queued", "running" => "Checking", "completed" => "Done", "failed" => "Didn't finish",
    "new" => "New", "saved" => "Saved", "dismissed" => "Passed",
    "settled" => "Paid", "pending" => "Pending", "voided" => "Voided"
  }.freeze

  VERDICT_TONES = { "grail" => "success", "strong" => "info", "maybe" => "warning", "pass" => "muted" }.freeze

  # Traces, tokens, transcripts and scoring internals are for the people
  # running the service, not the collectors using it.
  def developer_details?
    current_user&.admin? == true
  end

  def page_title(title)
    content_for(:title, "#{title} | Grail Hunter")
  end

  def money(cents, currency = "USD")
    return "n/a" if cents.nil?

    unit = CURRENCY_SYMBOLS.fetch(currency.to_s.upcase) { "#{currency} " }
    number_to_currency(cents / 100.0, unit: unit, precision: (cents % 100).zero? ? 0 : 2)
  end

  def fee_label(plan)
    plan.free_runs? ? "checks included" : "#{money(plan.run_fee_cents)} per check"
  end

  def status_badge(status)
    tag.span(STATUS_LABELS.fetch(status.to_s) { status.to_s.humanize }, class: "badge badge-#{STATUS_TONES.fetch(status.to_s, 'muted')}")
  end

  def verdict_badge(finding)
    return "".html_safe if finding.verdict.blank?

    tag.span(finding.verdict_label, class: "badge badge-#{VERDICT_TONES.fetch(finding.verdict, 'muted')}")
  end

  def score_bar(score)
    score = score.to_i
    tag.div(class: "score", title: "#{score}% match") do
      tag.div(class: "score-track") { tag.div("", class: "score-fill", style: "width: #{score}%") } +
        tag.span("#{score}%", class: "score-value")
    end
  end

  def schedule_label(hunt)
    return "Paused" if hunt.paused?
    hunt.scheduled? ? "Checking #{hunt.frequency_label.downcase}" : "Checks when you ask"
  end

  def time_ago(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end

  def duration_label(seconds)
    return "n/a" unless seconds

    seconds < 1 ? "#{(seconds * 1000).round}ms" : "#{seconds.round(1)}s"
  end

  # Links a run to its trace on the dashboard for admins; everyone else
  # sees the id. The dashboard's trace page is keyed by the trace row, so
  # the id the run stores (the telemetry trace_id) is looked up first.
  def trace_link(trace_id)
    return tag.span("no trace", class: "mono dim") if trace_id.blank?

    short = trace_id.to_s.first(8)
    if current_user&.admin? && (trace = ActionAgent::TelemetryTrace.find_by(trace_id: trace_id))
      link_to "trace #{short}", "/activeagents/traces/#{trace.id}", class: "mono link", title: trace_id
    else
      tag.span("trace #{short}", class: "mono dim", title: trace_id)
    end
  end

  # A finding's picture: the marketplace thumbnail a live backend found, the
  # category tile the sample catalog ships, or the "no photo" tile.
  def listing_image(finding)
    finding.image_url.presence || "/catalog/placeholder.svg"
  end

  # The tile to show when a listing's picture will not load.
  def category_tile(hunt)
    "/catalog/#{hunt.category.presence_in(Hunt::CATEGORIES) || 'other'}.svg"
  end

  # A listing picture with the fallback wired up.
  def listing_image_tag(finding, **options)
    image_tag listing_image(finding), alt: finding.title, loading: "lazy",
              data: { controller: "image-fallback", action: "error->image-fallback#replace",
                      image_fallback_src_value: category_tile(finding.hunt) }, **options
  end

  # Attribution for a sample catalog picture; nil for marketplace thumbnails.
  def image_credit(finding)
    ProductSearch::Backends::Catalog.credit_for(finding.image_url)
  end

  def nav_link(label, path, glyph: nil)
    active = current_page?(path) || (path != root_path && request.path.start_with?(path))
    link_to path, class: "nav-link #{'is-active' if active}" do
      safe_join([ (tag.span(glyph, class: "glyph") if glyph), label ].compact, " ")
    end
  end
end
