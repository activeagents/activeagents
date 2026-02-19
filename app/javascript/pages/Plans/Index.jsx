import { router } from '@inertiajs/react'
import { useState } from 'react'

export default function PlansIndex({ plans, current_plan, signed_in }) {
  const [billingInterval, setBillingInterval] = useState('monthly')

  function handleSelectPlan(plan) {
    if (plan.free) return

    if (!signed_in) {
      router.visit('/registration/new')
      return
    }

    router.post('/subscriptions/checkout', {
      plan_id: plan.id,
      billing_interval: billingInterval,
    })
  }

  return (
    <div className="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <div className="text-center">
          <h2 className="text-3xl font-extrabold text-gray-900 sm:text-4xl">
            Choose your plan
          </h2>
          <p className="mt-4 text-xl text-gray-600">
            Start free, scale as you grow.
          </p>
        </div>

        <div className="mt-8 flex justify-center">
          <div className="relative flex rounded-lg bg-gray-200 p-1">
            <button
              type="button"
              className={`relative rounded-md py-2 px-6 text-sm font-medium whitespace-nowrap focus:outline-none ${
                billingInterval === 'monthly'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-700'
              }`}
              onClick={() => setBillingInterval('monthly')}
            >
              Monthly
            </button>
            <button
              type="button"
              className={`relative ml-0.5 rounded-md py-2 px-6 text-sm font-medium whitespace-nowrap focus:outline-none ${
                billingInterval === 'annual'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-700'
              }`}
              onClick={() => setBillingInterval('annual')}
            >
              Annual <span className="text-green-600 text-xs font-semibold">Save ~16%</span>
            </button>
          </div>
        </div>

        <div className="mt-12 grid gap-8 lg:grid-cols-3">
          {plans.map((plan) => (
            <div
              key={plan.id}
              className={`relative flex flex-col rounded-2xl border ${
                plan.slug === 'pro' ? 'border-indigo-600 shadow-xl' : 'border-gray-200'
              } bg-white p-8`}
            >
              {plan.slug === 'pro' && (
                <div className="absolute -top-4 left-1/2 -translate-x-1/2">
                  <span className="inline-flex rounded-full bg-indigo-600 px-4 py-1 text-xs font-semibold text-white">
                    Most Popular
                  </span>
                </div>
              )}

              <div className="flex-1">
                <h3 className="text-xl font-semibold text-gray-900">{plan.name}</h3>

                <div className="mt-4 flex items-baseline">
                  <span className="text-4xl font-extrabold text-gray-900">
                    ${billingInterval === 'annual' ? plan.annual_price_dollars : plan.price_dollars}
                  </span>
                  {!plan.free && (
                    <span className="ml-1 text-xl font-semibold text-gray-500">
                      /{billingInterval === 'annual' ? 'yr' : 'mo'}
                    </span>
                  )}
                </div>

                {plan.trial_days > 0 && (
                  <p className="mt-2 text-sm text-green-600">
                    {plan.trial_days}-day free trial
                  </p>
                )}

                <ul className="mt-6 space-y-4">
                  <li className="flex items-start">
                    <span className="text-sm text-gray-600">
                      {plan.included_seats === -1
                        ? 'Unlimited team seats'
                        : `${plan.included_seats} team seat${plan.included_seats !== 1 ? 's' : ''}`}
                    </span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-sm text-gray-600">
                      {plan.included_workspaces === 0
                        ? 'No workspaces'
                        : plan.included_workspaces === -1
                        ? 'Unlimited workspaces'
                        : `${plan.included_workspaces} workspace${plan.included_workspaces !== 1 ? 's' : ''}`}
                    </span>
                  </li>
                  {plan.features &&
                    Object.entries(plan.features).map(([key, value]) =>
                      value === true ? (
                        <li key={key} className="flex items-start">
                          <svg className="h-5 w-5 flex-shrink-0 text-green-500" viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                          </svg>
                          <span className="ml-2 text-sm text-gray-600">
                            {key.replace(/_/g, ' ').replace(/\b\w/g, (l) => l.toUpperCase())}
                          </span>
                        </li>
                      ) : null
                    )}
                </ul>
              </div>

              <div className="mt-8">
                {current_plan?.id === plan.id ? (
                  <button
                    disabled
                    className="w-full rounded-md bg-gray-100 py-3 px-4 text-sm font-semibold text-gray-500 cursor-not-allowed"
                  >
                    Current Plan
                  </button>
                ) : plan.free ? (
                  <a
                    href="https://github.com/activeagents/activeagent"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="block w-full rounded-md border border-gray-300 bg-white py-3 px-4 text-center text-sm font-semibold text-gray-700 hover:bg-gray-50"
                  >
                    Get Started
                  </a>
                ) : plan.slug === 'enterprise' ? (
                  <a
                    href="mailto:sales@activeagent.com?subject=Enterprise Plan Inquiry"
                    className="block w-full rounded-md bg-gray-800 hover:bg-gray-900 py-3 px-4 text-center text-sm font-semibold text-white"
                  >
                    Contact Sales
                  </a>
                ) : (
                  <button
                    onClick={() => handleSelectPlan(plan)}
                    className="w-full rounded-md py-3 px-4 text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-700"
                  >
                    Subscribe
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
