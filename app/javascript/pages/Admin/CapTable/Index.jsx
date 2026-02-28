import React from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function CapTableContent({ entries, summary, pending_safes }) {
  const { darkMode, toggleDarkMode } = useTheme()

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const formatCurrency = (amount) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 0 }).format(amount || 0)
  const formatNumber = (num) => new Intl.NumberFormat('en-US').format(num || 0)
  const formatPercent = (num) => `${(num || 0).toFixed(2)}%`

  const typeColors = {
    founder: '#8b5cf6',
    investor: '#22c55e',
    employee: '#3b82f6',
    advisor: '#f59e0b'
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '32px' }}>
      <div style={{ position: 'fixed', top: '16px', right: '16px', zIndex: 50 }}>
        <button onClick={toggleDarkMode} style={{ padding: '8px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', border: 'none', cursor: 'pointer' }}>{darkMode ? '☀️' : '🌙'}</button>
      </div>

      <div style={{ maxWidth: '1280px', margin: '0 auto' }}>
        <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, marginBottom: '8px' }}>Cap Table</h1>
        <p style={{ color: colors.textSecondary, marginBottom: '32px' }}>View your company's ownership structure</p>

        {/* Summary */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '16px', marginBottom: '32px' }}>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Founders</div>
            <div style={{ color: '#8b5cf6', fontSize: '24px', fontWeight: '700', marginTop: '4px' }}>{formatPercent(summary.by_type.founders)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Investors</div>
            <div style={{ color: '#22c55e', fontSize: '24px', fontWeight: '700', marginTop: '4px' }}>{formatPercent(summary.by_type.investors)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Employees</div>
            <div style={{ color: '#3b82f6', fontSize: '24px', fontWeight: '700', marginTop: '4px' }}>{formatPercent(summary.by_type.employees)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Total Shares</div>
            <div style={{ color: colors.textPrimary, fontSize: '24px', fontWeight: '700', marginTop: '4px' }}>{formatNumber(summary.total_shares)}</div>
          </div>
        </div>

        {/* Cap Table */}
        <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', overflow: 'hidden', marginBottom: '32px' }}>
          <div style={{ padding: '20px', borderBottom: `1px solid ${colors.border}` }}>
            <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, margin: 0 }}>Equity Holders</h2>
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Stakeholder</th>
                <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Type</th>
                <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Security</th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Shares</th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Ownership</th>
              </tr>
            </thead>
            <tbody>
              {entries.map(entry => (
                <tr key={entry.id} style={{ borderBottom: `1px solid ${colors.border}` }}>
                  <td style={{ padding: '16px', color: colors.textPrimary, fontWeight: '500' }}>{entry.stakeholder_name}</td>
                  <td style={{ padding: '16px', textAlign: 'center' }}>
                    <span style={{ padding: '4px 8px', borderRadius: '4px', backgroundColor: typeColors[entry.stakeholder_type] + '20', color: typeColors[entry.stakeholder_type], fontSize: '12px', fontWeight: '500', textTransform: 'capitalize' }}>
                      {entry.stakeholder_type}
                    </span>
                  </td>
                  <td style={{ padding: '16px', color: colors.textSecondary }}>{entry.security_label}</td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textPrimary }}>{formatNumber(entry.shares)}</td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textPrimary, fontWeight: '600' }}>{formatPercent(entry.ownership_percent)}</td>
                </tr>
              ))}
              {entries.length === 0 && (
                <tr><td colSpan="5" style={{ padding: '48px', textAlign: 'center', color: colors.textSecondary }}>No cap table entries yet</td></tr>
              )}
            </tbody>
          </table>
        </div>

        {/* Pending SAFEs */}
        {pending_safes.length > 0 && (
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', overflow: 'hidden' }}>
            <div style={{ padding: '20px', borderBottom: `1px solid ${colors.border}` }}>
              <h2 style={{ fontSize: '18px', fontWeight: '600', color: colors.textPrimary, margin: 0 }}>Pending SAFEs (Not Yet Converted)</h2>
            </div>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                  <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Investor</th>
                  <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Amount</th>
                  <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Val Cap</th>
                  <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Type</th>
                </tr>
              </thead>
              <tbody>
                {pending_safes.map(safe => (
                  <tr key={safe.id} style={{ borderBottom: `1px solid ${colors.border}` }}>
                    <td style={{ padding: '16px', color: colors.textPrimary, fontWeight: '500' }}>{safe.investor_name}</td>
                    <td style={{ padding: '16px', textAlign: 'right', color: colors.textPrimary }}>{formatCurrency(safe.investment_amount)}</td>
                    <td style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary }}>{safe.valuation_cap ? formatCurrency(safe.valuation_cap) : 'MFN'}</td>
                    <td style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, textTransform: 'capitalize' }}>{safe.safe_type.replace('_', ' ')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

export default function CapTableIndex(props) {
  return (
    <ThemeProvider>
      <CapTableContent {...props} />
    </ThemeProvider>
  )
}
