export default function SubscriptionsIndex({ current_plan, subscription, plans }) {
  function formatPrice(cents) {
    return `$${(cents / 100).toFixed(0)}`
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 justify-between items-center">
            <span className="text-xl font-bold text-indigo-600">ActiveAgent</span>
            <div className="flex items-center space-x-4">
              <a href="/dashboard" className="text-sm text-gray-600 hover:text-gray-900">Dashboard</a>
              <a href="/subscriptions" className="text-sm font-medium text-indigo-600">Billing</a>
            </div>
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-4xl py-12 px-4 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold text-gray-900">Subscription & Billing</h1>

        {/* Current Plan Card */}
        <div className="mt-8 bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold text-gray-900">Current Plan</h2>
          <div className="mt-4 flex items-center justify-between">
            <div>
              <p className="text-2xl font-bold text-gray-900">
                {current_plan ? current_plan.name : 'No Plan'}
              </p>
              {current_plan && !current_plan.free && current_plan.price_cents > 0 && (
                <p className="text-sm text-gray-500">
                  {formatPrice(current_plan.price_cents)}/mo
                  {current_plan.slug === 'enterprise' ? ' per 100 agents' : ''}
                  {current_plan.annual_price_cents > 0 ? ` or ${formatPrice(current_plan.annual_price_cents)}/year` : ''}
                </p>
              )}
              {current_plan && current_plan.free && (
                <p className="text-sm text-gray-500">Free forever — community tier</p>
              )}
            </div>
            {subscription && (
              <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${
                subscription.active
                  ? 'bg-green-100 text-green-800'
                  : subscription.on_trial
                  ? 'bg-blue-100 text-blue-800'
                  : subscription.canceled
                  ? 'bg-yellow-100 text-yellow-800'
                  : 'bg-red-100 text-red-800'
              }`}>
                {subscription.on_trial ? 'Trial' : subscription.active ? 'Active' : subscription.canceled ? 'Canceled' : subscription.status}
              </span>
            )}
          </div>

          {subscription && (
            <div className="mt-4 border-t pt-4">
              {subscription.on_trial && subscription.trial_ends_at && (
                <p className="text-sm text-gray-600">
                  Trial ends: {new Date(subscription.trial_ends_at).toLocaleDateString()}
                </p>
              )}
              {subscription.current_period_end && (
                <p className="text-sm text-gray-600">
                  Current period ends: {new Date(subscription.current_period_end).toLocaleDateString()}
                </p>
              )}
              {subscription.canceled && subscription.on_grace_period && (
                <p className="text-sm text-yellow-600">
                  Your subscription has been canceled but you have access until the end of the billing period.
                </p>
              )}
            </div>
          )}

          {/* Action Buttons */}
          <div className="mt-6 flex space-x-4">
            {subscription && subscription.active && (
              <form action="/subscriptions/billing_portal" method="post">
                <input type="hidden" name="authenticity_token" value={document.querySelector('meta[name="csrf-token"]')?.content || ''} />
                <button
                  type="submit"
                  className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                >
                  Manage Billing
                </button>
              </form>
            )}
            {subscription && subscription.canceled && subscription.on_grace_period && (
              <form action="/subscriptions/resume" method="post">
                <input type="hidden" name="authenticity_token" value={document.querySelector('meta[name="csrf-token"]')?.content || ''} />
                <button
                  type="submit"
                  className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700"
                >
                  Resume Subscription
                </button>
              </form>
            )}
          </div>
        </div>

        {/* Available Plans */}
        {(!subscription || !subscription.active) && (
          <div className="mt-8">
            <h2 className="text-lg font-semibold text-gray-900">Available Plans</h2>
            <div className="mt-4 grid gap-6 md:grid-cols-3">
              {plans && plans.filter(p => !p.free).map(plan => (
                <div key={plan.id} className="bg-white rounded-lg shadow p-6">
                  <h3 className="font-semibold text-gray-900">{plan.name}</h3>
                  <p className="mt-2 text-2xl font-bold">
                    {formatPrice(plan.price_cents)}+
                    <span className="text-sm text-gray-500">
                      /mo{plan.slug === 'enterprise' ? ' per 100 agents' : ''}
                    </span>
                  </p>
                  {plan.annual_price_cents > 0 && (
                    <p className="text-sm text-gray-500">
                      or {formatPrice(plan.annual_price_cents)}/year
                    </p>
                  )}
                  <p className="mt-2 text-sm text-gray-600">
                    {plan.included_seats === -1 ? 'Unlimited' : plan.included_seats} seats
                  </p>
                  {plan.trial_days > 0 && (
                    <p className="text-sm text-indigo-600">{plan.trial_days}-day free trial</p>
                  )}
                  {plan.slug === 'enterprise' ? (
                    <a
                      href="mailto:sales@activeagents.ai"
                      className="mt-4 block w-full text-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                    >
                      Contact Sales
                    </a>
                  ) : (
                    <form action="/subscriptions/checkout" method="post" className="mt-4">
                      <input type="hidden" name="authenticity_token" value={document.querySelector('meta[name="csrf-token"]')?.content || ''} />
                      <input type="hidden" name="plan" value={plan.slug} />
                      <input type="hidden" name="interval" value="monthly" />
                      <button
                        type="submit"
                        className="w-full px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700"
                      >
                        {plan.trial_days > 0 ? 'Start Free Trial' : 'Subscribe'}
                      </button>
                    </form>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
