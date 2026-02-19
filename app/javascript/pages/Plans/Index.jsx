import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../contexts/ThemeContext'

function PlansContent({ plans, current_plan, signed_in }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const [billingInterval, setBillingInterval] = useState('monthly')

  // Theme colors - single source of truth
  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
    toggleBg: darkMode ? '#2a2a2a' : '#e5e7eb',
    toggleActive: darkMode ? '#1a1a1a' : '#ffffff',
  }

  async function handleSelectPlan(plan) {
    if (plan.free) return

    if (!signed_in) {
      router.visit('/registration/new')
      return
    }

    try {
      const response = await fetch('/subscriptions/checkout', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Inertia': 'true',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
        },
        body: JSON.stringify({
          plan_id: plan.id,
          billing_interval: billingInterval,
        }),
      })

      const data = await response.json()
      if (data.checkout_url) {
        window.location.href = data.checkout_url
      }
    } catch (error) {
      console.error('Checkout error:', error)
    }
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '48px 16px' }}>
      {/* Theme toggle in top right */}
      <div style={{ position: 'fixed', top: '16px', right: '16px', zIndex: 50 }}>
        <button
          onClick={toggleDarkMode}
          style={{
            padding: '8px',
            borderRadius: '8px',
            backgroundColor: darkMode ? '#252525' : '#f3f4f6',
            color: darkMode ? '#fbbf24' : '#4b5563',
            border: 'none',
            cursor: 'pointer'
          }}
          title={darkMode ? 'Switch to light mode' : 'Switch to dark mode'}
        >
          {darkMode ? (
            <svg style={{ width: '20px', height: '20px' }} fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg style={{ width: '20px', height: '20px' }} fill="currentColor" viewBox="0 0 20 20">
              <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
            </svg>
          )}
        </button>
      </div>

      <div style={{ maxWidth: '1280px', margin: '0 auto' }}>
        <div style={{ textAlign: 'center' }}>
          <h2 style={{ fontSize: '36px', fontWeight: '800', color: colors.textPrimary }}>
            Choose your plan
          </h2>
          <p style={{ marginTop: '16px', fontSize: '20px', color: colors.textSecondary }}>
            Start free, scale as you grow.
          </p>
        </div>

        {/* Billing toggle */}
        <div style={{ marginTop: '32px', display: 'flex', justifyContent: 'center' }}>
          <div style={{
            position: 'relative',
            display: 'flex',
            borderRadius: '8px',
            backgroundColor: colors.toggleBg,
            padding: '4px'
          }}>
            <button
              type="button"
              onClick={() => setBillingInterval('monthly')}
              style={{
                position: 'relative',
                borderRadius: '6px',
                padding: '8px 24px',
                fontSize: '14px',
                fontWeight: '500',
                whiteSpace: 'nowrap',
                border: 'none',
                cursor: 'pointer',
                backgroundColor: billingInterval === 'monthly' ? colors.toggleActive : 'transparent',
                color: billingInterval === 'monthly' ? colors.textPrimary : colors.textSecondary,
                boxShadow: billingInterval === 'monthly' ? '0 1px 2px rgba(0,0,0,0.1)' : 'none'
              }}
            >
              Monthly
            </button>
            <button
              type="button"
              onClick={() => setBillingInterval('annual')}
              style={{
                position: 'relative',
                marginLeft: '2px',
                borderRadius: '6px',
                padding: '8px 24px',
                fontSize: '14px',
                fontWeight: '500',
                whiteSpace: 'nowrap',
                border: 'none',
                cursor: 'pointer',
                backgroundColor: billingInterval === 'annual' ? colors.toggleActive : 'transparent',
                color: billingInterval === 'annual' ? colors.textPrimary : colors.textSecondary,
                boxShadow: billingInterval === 'annual' ? '0 1px 2px rgba(0,0,0,0.1)' : 'none'
              }}
            >
              Annual <span style={{ color: '#16a34a', fontSize: '12px', fontWeight: '600' }}>Save ~16%</span>
            </button>
          </div>
        </div>

        {/* Plan cards */}
        <div style={{
          marginTop: '48px',
          display: 'grid',
          gap: '32px',
          gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))'
        }}>
          {plans.map((plan) => (
            <div
              key={plan.id}
              style={{
                position: 'relative',
                display: 'flex',
                flexDirection: 'column',
                borderRadius: '16px',
                border: plan.slug === 'pro' ? '2px solid #ef4444' : `1px solid ${colors.border}`,
                backgroundColor: colors.cardBg,
                padding: '32px',
                boxShadow: plan.slug === 'pro' ? '0 25px 50px -12px rgba(0, 0, 0, 0.25)' : 'none'
              }}
            >
              {plan.slug === 'pro' && (
                <div style={{
                  position: 'absolute',
                  top: '-12px',
                  left: '50%',
                  transform: 'translateX(-50%)'
                }}>
                  <span style={{
                    display: 'inline-flex',
                    borderRadius: '9999px',
                    backgroundColor: '#ef4444',
                    padding: '4px 16px',
                    fontSize: '12px',
                    fontWeight: '600',
                    color: '#ffffff'
                  }}>
                    Most Popular
                  </span>
                </div>
              )}

              <div style={{ flex: 1 }}>
                <h3 style={{ fontSize: '20px', fontWeight: '600', color: colors.textPrimary }}>{plan.name}</h3>

                <div style={{ marginTop: '16px', display: 'flex', alignItems: 'baseline' }}>
                  <span style={{ fontSize: '36px', fontWeight: '800', color: colors.textPrimary }}>
                    ${billingInterval === 'annual' ? plan.annual_price_dollars : plan.price_dollars}
                  </span>
                  {!plan.free && (
                    <span style={{ marginLeft: '4px', fontSize: '20px', fontWeight: '600', color: colors.textSecondary }}>
                      /{billingInterval === 'annual' ? 'yr' : 'mo'}
                    </span>
                  )}
                </div>

                {plan.trial_days > 0 && (
                  <p style={{ marginTop: '8px', fontSize: '14px', color: '#16a34a' }}>
                    {plan.trial_days}-day free trial
                  </p>
                )}

                <ul style={{ marginTop: '24px', listStyle: 'none', padding: 0 }}>
                  <li style={{ display: 'flex', alignItems: 'flex-start', marginBottom: '16px' }}>
                    <span style={{ fontSize: '14px', color: colors.textSecondary }}>
                      {plan.included_seats} team seat{plan.included_seats !== 1 ? 's' : ''}
                    </span>
                  </li>
                  <li style={{ display: 'flex', alignItems: 'flex-start', marginBottom: '16px' }}>
                    <span style={{ fontSize: '14px', color: colors.textSecondary }}>
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
                        <li key={key} style={{ display: 'flex', alignItems: 'flex-start', marginBottom: '16px' }}>
                          <svg style={{ height: '20px', width: '20px', flexShrink: 0, color: '#22c55e' }} viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                          </svg>
                          <span style={{ marginLeft: '8px', fontSize: '14px', color: colors.textSecondary }}>
                            {key.replace(/_/g, ' ').replace(/\b\w/g, (l) => l.toUpperCase())}
                          </span>
                        </li>
                      ) : null
                    )}
                </ul>
              </div>

              <div style={{ marginTop: '32px' }}>
                {current_plan?.id === plan.id ? (
                  <button
                    disabled
                    style={{
                      width: '100%',
                      borderRadius: '6px',
                      backgroundColor: darkMode ? '#2a2a2a' : '#f3f4f6',
                      padding: '12px 16px',
                      fontSize: '14px',
                      fontWeight: '600',
                      color: colors.textMuted,
                      cursor: 'not-allowed',
                      border: 'none'
                    }}
                  >
                    Current Plan
                  </button>
                ) : plan.free ? (
                  <a
                    href="https://github.com/activeagents/activeagent"
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{
                      display: 'block',
                      width: '100%',
                      borderRadius: '6px',
                      border: `1px solid ${colors.border}`,
                      backgroundColor: colors.cardBg,
                      padding: '12px 16px',
                      textAlign: 'center',
                      fontSize: '14px',
                      fontWeight: '600',
                      color: colors.textSecondary,
                      textDecoration: 'none',
                      boxSizing: 'border-box'
                    }}
                  >
                    Get Started
                  </a>
                ) : (
                  <button
                    onClick={() => handleSelectPlan(plan)}
                    style={{
                      width: '100%',
                      borderRadius: '6px',
                      padding: '12px 16px',
                      fontSize: '14px',
                      fontWeight: '600',
                      color: '#ffffff',
                      border: 'none',
                      cursor: 'pointer',
                      backgroundColor: plan.slug === 'pro' ? '#ef4444' : (darkMode ? '#374151' : '#1f2937')
                    }}
                  >
                    {plan.slug === 'enterprise' ? 'Contact Sales' : 'Subscribe'}
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

export default function PlansIndex(props) {
  return (
    <ThemeProvider>
      <PlansContent {...props} />
    </ThemeProvider>
  )
}
