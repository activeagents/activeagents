// Shared by the signup and newsletter controllers: the HumanCheck fields a
// form carries (see app/helpers/human_check_helper.rb), read into a JSON body,
// and the Turnstile widget reset after a refused submission.

export const HONEYPOT_FIELD = "website"
export const TOKEN_FIELD = "cf-turnstile-response"

// The honeypot and Turnstile values of `form`, keyed as the server expects.
// A form without the fields contributes nothing, so the body is unchanged
// when Turnstile is off.
export function humanCheckFields(form) {
  const fields = {}
  const honeypot = form.querySelector(`[name="${HONEYPOT_FIELD}"]`)
  if (honeypot) fields[HONEYPOT_FIELD] = honeypot.value
  const token = form.querySelector(`[name="${TOKEN_FIELD}"]`)
  if (token) fields[TOKEN_FIELD] = token.value
  return fields
}

// Turnstile tokens are single use: ask the widget for a new one before the
// person retries.
export function resetHumanCheck(form) {
  form.querySelectorAll("[data-controller~='turnstile']").forEach((widget) => {
    widget.dispatchEvent(new CustomEvent("turnstile:reset"))
  })
}
