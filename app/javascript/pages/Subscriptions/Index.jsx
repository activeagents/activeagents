import { router } from '@inertiajs/react'

export default function SubscriptionsIndex({ subscription, plan, plans, stripe_public_key }) {
  function handleBillingPortal() {
    router.post('/subscriptions/billing_portal')
  }

  function handleCancel(subscriptionId) {
    if (confirm('Are you sure you want to cancel your subscription? You will retain access until the end of the current billing period.')) {
      router.delete(`/subscriptions/${subscriptionId}`)
    }
  }

  function handleResume() {
    router.post('/subscriptions/resume')
  }

  function handleChangePlan(planId, interval) {
    router.patch('/subscriptions/change_plan', {
      plan_id: planId,
      billing_interval: interval || 'monthly',
    })
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 justify-between items-center">
            <span className="text-xl font-bold text-indigo-600">Active Agents</span>
            <div className="flex items-center space-x-4">
              <a href="/dashboard" className="text-sm text-gray-700 hover:text-gray-900">Dashboard</a>
              <a href="/plans" className="text-sm text-gray-700 hover:text-gray-900">Plans</a>
            </div>
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-4xl py-12 px-4 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold text-gray-900">Subscription</h1>

        {subscription ? (
          <div className="mt-8 bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-semibold text-gray-900">
                  {plan?.name || 'Current Plan'}
                </h2>
                <div className="mt-1 flex items-center space-x-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                      subscription.active
                        ? 'bg-green-100 text-green-800'
                        : 'bg-yellow-100 text-yellow-800'
                    }`}
                  >
                    {subscription.on_trial
                      ? 'Trial'
                      : subscription.cancelled
                      ? 'Cancelled'
                      : subscription.status}
                  </span>
                </div>
              </div>

              <div className="text-right">
                {plan && (
                  <p className="text-2xl font-bold text-gray-900">
                    ${plan.price_dollars}
                    <span className="text-base font-normal text-gray-500">/mo</span>
                  </p>
                )}
              </div>
            </div>

            {subscription.on_trial && subscription.trial_ends_at && (
              <div className="mt-4 rounded-md bg-blue-50 p-4">
                <p className="text-sm text-blue-700">
                  Your trial ends on {new Date(subscription.trial_ends_at).toLocaleDateString()}.
                </p>
              </div>
            )}

            {subscription.cancelled && subscription.ends_at && (
              <div className="mt-4 rounded-md bg-yellow-50 p-4">
                <p className="text-sm text-yellow-700">
                  Your subscription is cancelled and will end on{' '}
                  {new Date(subscription.ends_at).toLocaleDateString()}.
                </p>
              </div>
            )}

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                onClick={handleBillingPortal}
                className="rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
              >
                Manage Billing
              </button>

              {subscription.cancelled ? (
                <button
                  onClick={handleResume}
                  className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
                >
                  Resume Subscription
                </button>
              ) : (
                <button
                  onClick={() => handleCancel(subscription.id)}
                  className="rounded-md bg-red-50 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-100"
                >
                  Cancel Subscription
                </button>
              )}
            </div>

            {/* Plan switching */}
            {!subscription.cancelled && plans && plans.length > 1 && (
              <div className="mt-8 border-t pt-6">
                <h3 className="text-lg font-medium text-gray-900">Switch Plan</h3>
                <div className="mt-4 grid gap-4 sm:grid-cols-3">
                  {plans
                    .filter((p) => !p.free && p.id !== plan?.id)
                    .map((p) => (
                      <div key={p.id} className="rounded-lg border border-gray-200 p-4">
                        <h4 className="font-semibold text-gray-900">{p.name}</h4>
                        <p className="mt-1 text-sm text-gray-500">${p.price_dollars}/mo</p>
                        <button
                          onClick={() => handleChangePlan(p.id, 'monthly')}
                          className="mt-3 w-full rounded-md bg-gray-800 px-3 py-2 text-xs font-semibold text-white hover:bg-gray-700"
                        >
                          Switch to {p.name}
                        </button>
                      </div>
                    ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="mt-8 bg-white rounded-lg shadow p-8 text-center">
            <h2 className="text-xl font-semibold text-gray-900">No active subscription</h2>
            <p className="mt-2 text-gray-600">Choose a plan to get started with Active Agents.</p>
            <a
              href="/plans"
              className="mt-6 inline-flex items-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
            >
              View Plans
            </a>
          </div>
        )}
      </div>
    </div>
  )
}
