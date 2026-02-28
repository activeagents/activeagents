import React from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function InvestorShowContent({ investor, safe_agreements, document_access, access_logs }) {
  const { darkMode, toggleDarkMode } = useTheme()

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const formatCurrency = (amount) => {
    if (!amount) return '$0'
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
    }).format(amount)
  }

  const formatDate = (dateString) => {
    if (!dateString) return 'N/A'
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const handleSendInvite = () => {
    router.post(`/admin/investors/${investor.id}/send_portal_invite`)
  }

  const handleRegenerateToken = () => {
    if (confirm('This will invalidate the current access link. Continue?')) {
      router.post(`/admin/investors/${investor.id}/regenerate_access_token`)
    }
  }

  const statusColors = {
    draft: { bg: '#6b7280', text: '#ffffff' },
    sent: { bg: '#f59e0b', text: '#ffffff' },
    signed: { bg: '#22c55e', text: '#ffffff' },
    converted: { bg: '#3b82f6', text: '#ffffff' },
    cancelled: { bg: '#ef4444', text: '#ffffff' }
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '32px' }}>
      {/* Theme toggle */}
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
        >
          {darkMode ? '☀️' : '🌙'}
        </button>
      </div>

      <div style={{ maxWidth: '1280px', margin: '0 auto' }}>
        {/* Back button */}
        <button
          onClick={() => router.visit('/admin/investors')}
          style={{
            marginBottom: '24px',
            padding: '8px 16px',
            backgroundColor: 'transparent',
            border: `1px solid ${colors.border}`,
            borderRadius: '8px',
            color: colors.textSecondary,
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          ← Back to Investors
        </button>

        {/* Header */}
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-start',
          marginBottom: '32px'
        }}>
          <div>
            <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, margin: 0 }}>
              {investor.name}
            </h1>
            <p style={{ color: colors.textSecondary, marginTop: '4px' }}>{investor.email}</p>
          </div>
          <div style={{ display: 'flex', gap: '12px' }}>
            <button
              onClick={handleSendInvite}
              style={{
                padding: '10px 20px',
                backgroundColor: '#FA343B',
                color: 'white',
                border: 'none',
                borderRadius: '8px',
                fontWeight: '600',
                cursor: 'pointer'
              }}
            >
              Send Portal Invite
            </button>
            <button
              onClick={() => router.visit(`/admin/investors/${investor.id}/edit`)}
              style={{
                padding: '10px 20px',
                backgroundColor: 'transparent',
                color: colors.textPrimary,
                border: `1px solid ${colors.border}`,
                borderRadius: '8px',
                fontWeight: '600',
                cursor: 'pointer'
              }}
            >
              Edit
            </button>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
          {/* Investor Details */}
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '24px'
          }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
              Details
            </h2>
            <div style={{ display: 'grid', gap: '16px' }}>
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Type</div>
                <div style={{ color: colors.textPrimary, textTransform: 'capitalize' }}>{investor.investor_type}</div>
              </div>
              {investor.legal_name && (
                <div>
                  <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Legal Name</div>
                  <div style={{ color: colors.textPrimary }}>{investor.legal_name}</div>
                </div>
              )}
              {investor.entity_name && (
                <div>
                  <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Entity</div>
                  <div style={{ color: colors.textPrimary }}>{investor.entity_name} ({investor.entity_type})</div>
                </div>
              )}
              {investor.phone && (
                <div>
                  <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Phone</div>
                  <div style={{ color: colors.textPrimary }}>{investor.phone}</div>
                </div>
              )}
              {investor.address?.line1 && (
                <div>
                  <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Address</div>
                  <div style={{ color: colors.textPrimary }}>
                    {investor.address.line1}<br />
                    {investor.address.line2 && <>{investor.address.line2}<br /></>}
                    {investor.address.city}, {investor.address.state} {investor.address.postal_code}<br />
                    {investor.address.country}
                  </div>
                </div>
              )}
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Total Invested</div>
                <div style={{ color: colors.textPrimary, fontSize: '24px', fontWeight: '700' }}>{formatCurrency(investor.total_invested)}</div>
              </div>
            </div>
          </div>

          {/* Portal Access */}
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '24px'
          }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
              Portal Access
            </h2>
            <div style={{ display: 'grid', gap: '16px' }}>
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Status</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span style={{
                    display: 'inline-block',
                    width: '8px',
                    height: '8px',
                    borderRadius: '50%',
                    backgroundColor: investor.portal_enabled ? '#22c55e' : '#ef4444'
                  }} />
                  <span style={{ color: colors.textPrimary }}>{investor.portal_enabled ? 'Enabled' : 'Disabled'}</span>
                </div>
              </div>
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Access Token</div>
                <div style={{ color: investor.has_valid_access_token ? '#22c55e' : '#ef4444' }}>
                  {investor.has_valid_access_token ? 'Valid' : 'Expired or Not Set'}
                </div>
              </div>
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Token Expires</div>
                <div style={{ color: colors.textPrimary }}>{formatDate(investor.access_token_expires_at)}</div>
              </div>
              <div>
                <div style={{ color: colors.textSecondary, fontSize: '12px', textTransform: 'uppercase', marginBottom: '4px' }}>Last Accessed</div>
                <div style={{ color: colors.textPrimary }}>{formatDate(investor.last_accessed_at)}</div>
              </div>
              <button
                onClick={handleRegenerateToken}
                style={{
                  marginTop: '8px',
                  padding: '8px 16px',
                  backgroundColor: 'transparent',
                  border: `1px solid ${colors.border}`,
                  borderRadius: '6px',
                  color: colors.textSecondary,
                  cursor: 'pointer',
                  fontSize: '14px'
                }}
              >
                Regenerate Access Token
              </button>
            </div>
          </div>
        </div>

        {/* SAFE Agreements */}
        <div style={{
          marginTop: '24px',
          backgroundColor: colors.cardBg,
          border: `1px solid ${colors.border}`,
          borderRadius: '12px',
          padding: '24px'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, margin: 0 }}>
              SAFE Agreements
            </h2>
            <button
              onClick={() => router.visit(`/admin/safe_agreements/new?investor_id=${investor.id}`)}
              style={{
                padding: '8px 16px',
                backgroundColor: '#FA343B',
                color: 'white',
                border: 'none',
                borderRadius: '6px',
                fontWeight: '500',
                cursor: 'pointer',
                fontSize: '14px'
              }}
            >
              + New SAFE
            </button>
          </div>
          {safe_agreements.length > 0 ? (
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                  <th style={{ padding: '12px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Amount</th>
                  <th style={{ padding: '12px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Valuation Cap</th>
                  <th style={{ padding: '12px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Type</th>
                  <th style={{ padding: '12px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Status</th>
                  <th style={{ padding: '12px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Date</th>
                </tr>
              </thead>
              <tbody>
                {safe_agreements.map((safe) => (
                  <tr
                    key={safe.id}
                    onClick={() => router.visit(`/admin/safe_agreements/${safe.id}`)}
                    style={{ borderBottom: `1px solid ${colors.border}`, cursor: 'pointer' }}
                  >
                    <td style={{ padding: '12px', color: colors.textPrimary, fontWeight: '500' }}>
                      {formatCurrency(safe.investment_amount)}
                    </td>
                    <td style={{ padding: '12px', color: colors.textSecondary }}>
                      {safe.valuation_cap ? formatCurrency(safe.valuation_cap) : 'MFN'}
                    </td>
                    <td style={{ padding: '12px', color: colors.textSecondary, textTransform: 'capitalize' }}>
                      {safe.safe_type.replace('_', ' ')}
                    </td>
                    <td style={{ padding: '12px' }}>
                      <span style={{
                        padding: '4px 8px',
                        borderRadius: '4px',
                        backgroundColor: statusColors[safe.status]?.bg || '#6b7280',
                        color: statusColors[safe.status]?.text || '#ffffff',
                        fontSize: '12px',
                        fontWeight: '500'
                      }}>
                        {safe.display_status}
                      </span>
                    </td>
                    <td style={{ padding: '12px', textAlign: 'right', color: colors.textSecondary, fontSize: '14px' }}>
                      {formatDate(safe.created_at)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p style={{ color: colors.textSecondary, textAlign: 'center', padding: '32px' }}>
              No SAFE agreements yet
            </p>
          )}
        </div>

        {/* Document Access */}
        <div style={{
          marginTop: '24px',
          backgroundColor: colors.cardBg,
          border: `1px solid ${colors.border}`,
          borderRadius: '12px',
          padding: '24px'
        }}>
          <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
            Document Access
          </h2>
          {document_access.length > 0 ? (
            <div style={{ display: 'grid', gap: '12px' }}>
              {document_access.map((grant) => (
                <div key={grant.id} style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '12px',
                  backgroundColor: darkMode ? '#252525' : '#f9fafb',
                  borderRadius: '8px'
                }}>
                  <div>
                    <div style={{ color: colors.textPrimary, fontWeight: '500' }}>{grant.document.name}</div>
                    <div style={{ color: colors.textSecondary, fontSize: '12px' }}>{grant.document.document_type}</div>
                  </div>
                  <span style={{
                    padding: '4px 8px',
                    borderRadius: '4px',
                    backgroundColor: grant.active ? '#22c55e' : '#6b7280',
                    color: '#ffffff',
                    fontSize: '12px'
                  }}>
                    {grant.active ? 'Active' : 'Expired'}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p style={{ color: colors.textSecondary, textAlign: 'center', padding: '32px' }}>
              No documents shared with this investor
            </p>
          )}
        </div>

        {/* Access Logs */}
        <div style={{
          marginTop: '24px',
          backgroundColor: colors.cardBg,
          border: `1px solid ${colors.border}`,
          borderRadius: '12px',
          padding: '24px'
        }}>
          <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
            Recent Activity
          </h2>
          {access_logs.length > 0 ? (
            <div style={{ display: 'grid', gap: '8px' }}>
              {access_logs.slice(0, 10).map((log) => (
                <div key={log.id} style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '8px 0',
                  borderBottom: `1px solid ${colors.border}`
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ color: log.action === 'downloaded' ? '#f59e0b' : '#3b82f6', fontSize: '14px' }}>
                      {log.action === 'downloaded' ? '⬇️' : '👁️'}
                    </span>
                    <span style={{ color: colors.textPrimary, fontSize: '14px' }}>
                      {log.action === 'downloaded' ? 'Downloaded' : 'Viewed'} {log.document_name}
                    </span>
                  </div>
                  <span style={{ color: colors.textSecondary, fontSize: '12px' }}>
                    {formatDate(log.created_at)}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p style={{ color: colors.textSecondary, textAlign: 'center', padding: '32px' }}>
              No activity yet
            </p>
          )}
        </div>
      </div>
    </div>
  )
}

export default function InvestorShow(props) {
  return (
    <ThemeProvider>
      <InvestorShowContent {...props} />
    </ThemeProvider>
  )
}
