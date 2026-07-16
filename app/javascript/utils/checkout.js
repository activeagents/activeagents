// Starts a Stripe Checkout session for a plan and navigates to it.
//
// Shared by every "Upgrade" CTA (Organization page, agent runner, sandbox
// demo, pricing page) so the flow stays consistent: look up the plan,
// POST /subscriptions/checkout with Inertia headers, follow the returned
// URL. Throws with a human-readable message on failure so callers can
// surface it instead of failing silently.
export async function startCheckout({ planSlug = 'pro', billingInterval = 'monthly' } = {}) {
  const plansResponse = await fetch('/api/v1/plans');
  if (!plansResponse.ok) throw new Error('Could not load plans. Please try again.');
  const plansData = await plansResponse.json();
  const plans = Array.isArray(plansData) ? plansData : plansData.plans || [];
  const plan = plans.find((p) => p.slug === planSlug);
  if (!plan) throw new Error('Plan not found. Please contact support.');

  const response = await fetch('/subscriptions/checkout', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Inertia': 'true',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
    },
    body: JSON.stringify({ plan_id: plan.id, billing_interval: billingInterval }),
  });

  let data = null;
  try {
    data = await response.json();
  } catch {
    // Non-JSON response (e.g. an HTML error page) — fall through to the error below
  }

  if (!response.ok || !data?.checkout_url) {
    throw new Error(data?.error || 'Unable to start checkout. Please try again.');
  }

  window.location.href = data.checkout_url;
}
