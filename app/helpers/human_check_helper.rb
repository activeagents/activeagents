# frozen_string_literal: true

# Markup for the HumanCheck layers inside a public form: the honeypot field
# always, the Turnstile widget when Turnstile is on. Render it inside the form
# element so the widget's hidden response field is submitted with it.
module HumanCheckHelper
  # Explicit rendering: the turnstile Stimulus controller renders each widget
  # once this script has run, waiting on the script element's load event when
  # it connects first. No onload callback name is passed, so the loader never
  # looks for a global that an async script would usually run before any
  # controller could define it.
  TURNSTILE_SCRIPT_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"

  # The honeypot input plus, when enabled, the Turnstile widget container.
  # +theme+ is "light", "dark" or "auto"; +appearance+ "always" or
  # "interaction-only" (the widget stays invisible unless a challenge is
  # needed).
  def human_check_fields(theme: "auto", appearance: "interaction-only")
    safe_join([ human_check_honeypot, turnstile_widget(theme: theme, appearance: appearance) ].compact)
  end

  # A text field people never see. It is positioned off screen rather than
  # display:none because some form fillers skip hidden inputs, and it is
  # left out of the tab order and the accessibility tree.
  def human_check_honeypot
    tag.div(class: "human-check-honeypot", aria: { hidden: true },
            style: "position:absolute;left:-10000px;top:auto;width:1px;height:1px;overflow:hidden") do
      label_tag(HumanCheck::HONEYPOT_FIELD, "Website", for: "human-check-#{HumanCheck::HONEYPOT_FIELD}") +
        text_field_tag(HumanCheck::HONEYPOT_FIELD, nil, id: "human-check-#{HumanCheck::HONEYPOT_FIELD}",
                                                        tabindex: -1, autocomplete: "off")
    end
  end

  def turnstile_widget(theme: "auto", appearance: "interaction-only")
    return unless HumanCheck.enabled?

    tag.div(class: "human-check-turnstile",
            data: { controller: "turnstile", turnstile_sitekey_value: HumanCheck.site_key,
                    turnstile_theme_value: theme, turnstile_appearance_value: appearance })
  end

  # The Turnstile loader, for a layout's <head>. Nothing is emitted when
  # Turnstile is off, so pages never load third-party script for no reason.
  def turnstile_script_tag
    return unless HumanCheck.enabled?

    javascript_include_tag(TURNSTILE_SCRIPT_URL, async: true, defer: true)
  end
end
