export default function PlansIndex({ plans }) {
  function formatPrice(cents) {
    return `$${(cents / 100).toFixed(0)}`
  }

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="text-center">
          <h2 className="text-3xl font-extrabold text-gray-900">Choose Your Plan</h2>
          <p className="mt-4 text-lg text-gray-600">
            Rails-native AI framework with hosted observability, evaluation, and collaboration tools
          </p>
        </div>

        <div className="mt-12 grid gap-8 lg:grid-cols-3">
          {plans.map(plan => (
            <div
              key={plan.id}
              className={`rounded-lg bg-white shadow-lg overflow-hidden ${
                plan.slug === 'pro' ? 'ring-2 ring-indigo-600' : ''
              }`}
            >
              {plan.slug === 'pro' && (
                <div className="bg-indigo-600 text-white text-center py-2 text-sm font-medium">
                  Most Popular
                </div>
              )}
              <div className="p-8">
                <h3 className="text-xl font-semibold text-gray-900">{plan.name}</h3>
                <div className="mt-4">
                  {plan.free ? (
                    <span className="text-4xl font-extrabold text-gray-900">Free</span>
                  ) : (
                    <>
                      <span className="text-4xl font-extrabold text-gray-900">
                        {formatPrice(plan.price_cents)}+
                      </span>
                      <span className="text-lg text-gray-500">
                        /mo{plan.slug === 'enterprise' ? ' per 100 agents' : ''}
                      </span>
                      {plan.annual_price_cents > 0 && (
                        <p className="mt-1 text-sm text-gray-500">
                          or {formatPrice(plan.annual_price_cents)}/year
                          {plan.annual_savings_percent > 0 && (
                            <span className="ml-1 text-green-600 font-medium">
                              (save {plan.annual_savings_percent}%)
                            </span>
                          )}
                        </p>
                      )}
                    </>
                  )}
                </div>
                {plan.trial_days > 0 && (
                  <p className="mt-2 text-sm text-indigo-600 font-medium">
                    {plan.trial_days}-day free trial
                  </p>
                )}
                <div className="mt-6">
                  <p className="text-sm text-gray-600">
                    {plan.included_seats === -1 ? 'Unlimited' : plan.included_seats} team seat{plan.included_seats !== 1 ? 's' : ''}
                  </p>
                  <p className="text-sm text-gray-600">
                    {plan.included_workspaces === -1 ? 'Unlimited' : plan.included_workspaces} workspace{plan.included_workspaces !== 1 ? 's' : ''}
                  </p>
                </div>
                <div className="mt-6">
                  <ul className="space-y-2">
                    {plan.features.hosted_dashboard && (
                      <li className="flex items-center text-sm text-gray-600">
                        <span className="text-green-500 mr-2">✓</span> Hosted Dashboard
                      </li>
                    )}
                    {plan.features.cost_analytics && (
                      <li className="flex items-center text-sm text-gray-600">
                        <span className="text-green-500 mr-2">✓</span> Cost & Latency Analytics
                      </li>
                    )}
                    {plan.features.ab_testing && (
                      <li className="flex items-center text-sm text-gray-600">
                        <span className="text-green-500 mr-2">✓</span> A/B Prompt Testing
                      </li>
                    )}
                    {plan.features.sso && (
                      <li className="flex items-center text-sm text-gray-600">
                        <span className="text-green-500 mr-2">✓</span> SSO/SAML & RBAC
                      </li>
                    )}
                    {plan.features.soc2_hipaa && (
                      <li className="flex items-center text-sm text-gray-600">
                        <span className="text-green-500 mr-2">✓</span> SOC 2 Type II & HIPAA
                      </li>
                    )}
                  </ul>
                </div>
                <div className="mt-8">
                  {plan.free ? (
                    <a
                      href="https://github.com/activeagents/activeagent"
                      className="block w-full text-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                    >
                      Get Started
                    </a>
                  ) : plan.slug === 'enterprise' ? (
                    <a
                      href="mailto:sales@activeagents.ai"
                      className="block w-full text-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                    >
                      Contact Sales
                    </a>
                  ) : (
                    <a
                      href={`/subscriptions/checkout?plan=${plan.slug}&interval=monthly`}
                      data-method="post"
                      className="block w-full text-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700"
                    >
                      {plan.trial_days > 0 ? `Start ${plan.trial_days}-Day Free Trial` : 'Subscribe'}
                    </a>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
