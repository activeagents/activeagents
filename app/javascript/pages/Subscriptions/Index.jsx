import React from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../contexts/ThemeContext'

function SubscriptionsContent({ subscription, plan, plans, stripe_public_key }) {
  const { darkMode, toggleDarkMode } = useTheme()

  // Theme colors - single source of truth
  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    navBg: darkMode ? '#1a1a1a' : '#ffffff',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
    infoBg: darkMode ? 'rgba(59, 130, 246, 0.1)' : '#eff6ff',
    infoText: darkMode ? '#60a5fa' : '#1d4ed8',
    warningBg: darkMode ? 'rgba(234, 179, 8, 0.1)' : '#fefce8',
    warningText: darkMode ? '#fbbf24' : '#a16207',
  }

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
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg }}>
      {/* Navigation */}
      <nav style={{ backgroundColor: colors.navBg, boxShadow: '0 1px 3px rgba(0,0,0,0.1)', borderBottom: `1px solid ${colors.border}` }}>
        <div style={{ maxWidth: '1280px', margin: '0 auto', padding: '0 16px' }}>
          <div style={{ display: 'flex', height: '64px', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: '20px', fontWeight: 'bold', color: '#ef4444' }}>Active Agent</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
              <a href="/dashboard" style={{ fontSize: '14px', color: colors.textSecondary, textDecoration: 'none' }}>Dashboard</a>
              <a href="/plans" style={{ fontSize: '14px', color: colors.textSecondary, textDecoration: 'none' }}>Plans</a>
              {/* Theme toggle */}
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
          </div>
        </div>
      </nav>

      <div style={{ maxWidth: '896px', margin: '0 auto', padding: '48px 16px' }}>
        <h1 style={{ fontSize: '30px', fontWeight: 'bold', color: colors.textPrimary }}>Subscription</h1>

        {subscription ? (
          <div style={{ marginTop: '32px', backgroundColor: colors.cardBg, borderRadius: '8px', boxShadow: '0 1px 3px rgba(0,0,0,0.1)', padding: '24px', border: `1px solid ${colors.border}` }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div>
                <h2 style={{ fontSize: '20px', fontWeight: '600', color: colors.textPrimary }}>
                  {plan?.name || 'Current Plan'}
                </h2>
                <div style={{ marginTop: '4px', display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <span
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      borderRadius: '9999px',
                      padding: '2px 10px',
                      fontSize: '12px',
                      fontWeight: '500',
                      backgroundColor: subscription.active
                        ? (darkMode ? 'rgba(34, 197, 94, 0.2)' : '#dcfce7')
                        : (darkMode ? 'rgba(234, 179, 8, 0.2)' : '#fef9c3'),
                      color: subscription.active
                        ? (darkMode ? '#4ade80' : '#166534')
                        : (darkMode ? '#fbbf24' : '#a16207')
                    }}
                  >
                    {subscription.on_trial
                      ? 'Trial'
                      : subscription.cancelled
                      ? 'Cancelled'
                      : subscription.status}
                  </span>
                </div>
              </div>

              <div style={{ textAlign: 'right' }}>
                {plan && (
                  <p style={{ fontSize: '24px', fontWeight: 'bold', color: colors.textPrimary }}>
                    ${plan.price_dollars}
                    <span style={{ fontSize: '16px', fontWeight: 'normal', color: colors.textSecondary }}>/mo</span>
                  </p>
                )}
              </div>
            </div>

            {subscription.on_trial && subscription.trial_ends_at && (
              <div style={{ marginTop: '16px', borderRadius: '6px', backgroundColor: colors.infoBg, padding: '16px' }}>
                <p style={{ fontSize: '14px', color: colors.infoText }}>
                  Your trial ends on {new Date(subscription.trial_ends_at).toLocaleDateString()}.
                </p>
              </div>
            )}

            {subscription.cancelled && subscription.ends_at && (
              <div style={{ marginTop: '16px', borderRadius: '6px', backgroundColor: colors.warningBg, padding: '16px' }}>
                <p style={{ fontSize: '14px', color: colors.warningText }}>
                  Your subscription is cancelled and will end on{' '}
                  {new Date(subscription.ends_at).toLocaleDateString()}.
                </p>
              </div>
            )}

            <div style={{ marginTop: '24px', display: 'flex', flexWrap: 'wrap', gap: '12px' }}>
              <button
                onClick={handleBillingPortal}
                style={{
                  borderRadius: '6px',
                  backgroundColor: colors.cardBg,
                  padding: '8px 16px',
                  fontSize: '14px',
                  fontWeight: '600',
                  color: colors.textPrimary,
                  boxShadow: `inset 0 0 0 1px ${colors.border}`,
                  border: 'none',
                  cursor: 'pointer'
                }}
              >
                Manage Billing
              </button>

              {subscription.cancelled ? (
                <button
                  onClick={handleResume}
                  style={{
                    borderRadius: '6px',
                    backgroundColor: '#ef4444',
                    padding: '8px 16px',
                    fontSize: '14px',
                    fontWeight: '600',
                    color: '#ffffff',
                    border: 'none',
                    cursor: 'pointer'
                  }}
                >
                  Resume Subscription
                </button>
              ) : (
                <button
                  onClick={() => handleCancel(subscription.id)}
                  style={{
                    borderRadius: '6px',
                    backgroundColor: darkMode ? 'rgba(239, 68, 68, 0.1)' : '#fef2f2',
                    padding: '8px 16px',
                    fontSize: '14px',
                    fontWeight: '600',
                    color: '#ef4444',
                    border: 'none',
                    cursor: 'pointer'
                  }}
                >
                  Cancel Subscription
                </button>
              )}
            </div>

            {/* Plan switching */}
            {!subscription.cancelled && plans && plans.length > 1 && (
              <div style={{ marginTop: '32px', borderTop: `1px solid ${colors.border}`, paddingTop: '24px' }}>
                <h3 style={{ fontSize: '18px', fontWeight: '500', color: colors.textPrimary }}>Switch Plan</h3>
                <div style={{ marginTop: '16px', display: 'grid', gap: '16px', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))' }}>
                  {plans
                    .filter((p) => !p.free && p.id !== plan?.id)
                    .map((p) => (
                      <div key={p.id} style={{ borderRadius: '8px', border: `1px solid ${colors.border}`, padding: '16px', backgroundColor: darkMode ? 'rgba(255,255,255,0.02)' : '#ffffff' }}>
                        <h4 style={{ fontWeight: '600', color: colors.textPrimary }}>{p.name}</h4>
                        <p style={{ marginTop: '4px', fontSize: '14px', color: colors.textSecondary }}>${p.price_dollars}/mo</p>
                        <button
                          onClick={() => handleChangePlan(p.id, 'monthly')}
                          style={{
                            marginTop: '12px',
                            width: '100%',
                            borderRadius: '6px',
                            backgroundColor: darkMode ? '#374151' : '#1f2937',
                            padding: '8px 12px',
                            fontSize: '12px',
                            fontWeight: '600',
                            color: '#ffffff',
                            border: 'none',
                            cursor: 'pointer'
                          }}
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
          <div style={{ marginTop: '32px', backgroundColor: colors.cardBg, borderRadius: '8px', boxShadow: '0 1px 3px rgba(0,0,0,0.1)', padding: '32px', textAlign: 'center', border: `1px solid ${colors.border}` }}>
            <h2 style={{ fontSize: '20px', fontWeight: '600', color: colors.textPrimary }}>No active subscription</h2>
            <p style={{ marginTop: '8px', color: colors.textSecondary }}>Choose a plan to get started with Active Agent.</p>
            <a
              href="/plans"
              style={{
                marginTop: '24px',
                display: 'inline-flex',
                alignItems: 'center',
                borderRadius: '6px',
                backgroundColor: '#ef4444',
                padding: '8px 16px',
                fontSize: '14px',
                fontWeight: '600',
                color: '#ffffff',
                textDecoration: 'none'
              }}
            >
              View Plans
            </a>
          </div>
        )}
      </div>
    </div>
  )
}

export default function SubscriptionsIndex(props) {
  return (
    <ThemeProvider>
      <SubscriptionsContent {...props} />
    </ThemeProvider>
  )
}
