import React from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../contexts/ThemeContext'

function DashboardContent({ investor, company, safe_agreements, documents, ownership_summary }) {
  const { darkMode, toggleDarkMode } = useTheme()

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const formatCurrency = (amount) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 0 }).format(amount || 0)
  const formatPercent = (num) => `${(num || 0).toFixed(2)}%`
  const formatDate = (dateString) => dateString ? new Date(dateString).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'

  const statusColors = {
    draft: { bg: '#6b7280', text: '#ffffff' },
    sent: { bg: '#f59e0b', text: '#ffffff' },
    signed: { bg: '#22c55e', text: '#ffffff' },
    converted: { bg: '#3b82f6', text: '#ffffff' },
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg }}>
      {/* Header */}
      <header style={{ backgroundColor: colors.cardBg, borderBottom: `1px solid ${colors.border}`, padding: '16px 32px' }}>
        <div style={{ maxWidth: '1280px', margin: '0 auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Investor Portal</div>
            <div style={{ color: colors.textPrimary, fontSize: '20px', fontWeight: '600' }}>{company.name}</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
            <span style={{ color: colors.textSecondary }}>{investor.name}</span>
            <button onClick={toggleDarkMode} style={{ padding: '8px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', border: 'none', cursor: 'pointer' }}>{darkMode ? '☀️' : '🌙'}</button>
            <button onClick={() => router.delete('/investor/logout')} style={{ padding: '8px 16px', borderRadius: '6px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, color: colors.textSecondary, cursor: 'pointer' }}>Logout</button>
          </div>
        </div>
      </header>

      <main style={{ maxWidth: '1280px', margin: '0 auto', padding: '32px' }}>
        {/* Welcome */}
        <div style={{ marginBottom: '32px' }}>
          <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, margin: 0 }}>Welcome back, {investor.name.split(' ')[0]}</h1>
          <p style={{ color: colors.textSecondary, marginTop: '8px' }}>Here's an overview of your investment in {company.name}.</p>
        </div>

        {/* Summary Cards */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '32px' }}>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Total Invested</div>
            <div style={{ color: colors.textPrimary, fontSize: '32px', fontWeight: '700', marginTop: '8px' }}>{formatCurrency(investor.total_invested)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Ownership</div>
            <div style={{ color: colors.textPrimary, fontSize: '32px', fontWeight: '700', marginTop: '8px' }}>{formatPercent(ownership_summary.total_ownership_percent)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>SAFE Agreements</div>
            <div style={{ color: colors.textPrimary, fontSize: '32px', fontWeight: '700', marginTop: '8px' }}>{safe_agreements.length}</div>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
          {/* SAFEs */}
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px' }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>Your Investments</h2>
            {safe_agreements.length > 0 ? (
              <div style={{ display: 'grid', gap: '12px' }}>
                {safe_agreements.map(safe => (
                  <div key={safe.id} style={{ padding: '16px', backgroundColor: darkMode ? '#252525' : '#f9fafb', borderRadius: '8px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '8px' }}>
                      <div style={{ color: colors.textPrimary, fontWeight: '600', fontSize: '18px' }}>{formatCurrency(safe.investment_amount)}</div>
                      <span style={{ padding: '4px 8px', borderRadius: '4px', backgroundColor: statusColors[safe.status]?.bg, color: statusColors[safe.status]?.text, fontSize: '12px', fontWeight: '500' }}>{safe.display_status}</span>
                    </div>
                    <div style={{ color: colors.textSecondary, fontSize: '14px' }}>
                      {safe.valuation_cap ? `${formatCurrency(safe.valuation_cap)} cap` : 'MFN'} • {safe.safe_type.replace('_', ' ')} SAFE
                    </div>
                    {safe.status === 'converted' && (
                      <div style={{ color: '#3b82f6', fontSize: '14px', marginTop: '8px' }}>
                        Converted to {safe.conversion_shares?.toLocaleString()} shares ({safe.conversion_round_name})
                      </div>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <p style={{ color: colors.textSecondary, textAlign: 'center', padding: '24px' }}>No investments yet</p>
            )}
          </div>

          {/* Documents */}
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, margin: 0 }}>Documents</h2>
              <button onClick={() => router.visit('/investor/documents')} style={{ color: '#FA343B', backgroundColor: 'transparent', border: 'none', cursor: 'pointer', fontSize: '14px' }}>View All →</button>
            </div>
            {documents.length > 0 ? (
              <div style={{ display: 'grid', gap: '12px' }}>
                {documents.slice(0, 5).map(doc => (
                  <div
                    key={doc.id}
                    onClick={() => router.visit(`/investor/documents/${doc.id}`)}
                    style={{ padding: '12px', backgroundColor: darkMode ? '#252525' : '#f9fafb', borderRadius: '8px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '12px' }}
                  >
                    <div style={{ fontSize: '24px' }}>📄</div>
                    <div style={{ flex: 1 }}>
                      <div style={{ color: colors.textPrimary, fontWeight: '500' }}>{doc.name}</div>
                      <div style={{ color: colors.textSecondary, fontSize: '12px' }}>{doc.document_type_label}</div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p style={{ color: colors.textSecondary, textAlign: 'center', padding: '24px' }}>No documents available</p>
            )}
          </div>
        </div>

        {/* Ownership Breakdown */}
        {ownership_summary.entries.length > 0 && (
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px', marginTop: '24px' }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>Ownership Breakdown</h2>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                  <th style={{ padding: '12px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Security</th>
                  <th style={{ padding: '12px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Shares</th>
                  <th style={{ padding: '12px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px' }}>Ownership</th>
                </tr>
              </thead>
              <tbody>
                {ownership_summary.entries.map((entry, i) => (
                  <tr key={i} style={{ borderBottom: `1px solid ${colors.border}` }}>
                    <td style={{ padding: '12px', color: colors.textPrimary }}>{entry.security_label}</td>
                    <td style={{ padding: '12px', textAlign: 'right', color: colors.textPrimary }}>{entry.shares?.toLocaleString()}</td>
                    <td style={{ padding: '12px', textAlign: 'right', color: colors.textPrimary, fontWeight: '600' }}>{formatPercent(entry.ownership_percent)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </main>
    </div>
  )
}

export default function Dashboard(props) {
  return (
    <ThemeProvider>
      <DashboardContent {...props} />
    </ThemeProvider>
  )
}
