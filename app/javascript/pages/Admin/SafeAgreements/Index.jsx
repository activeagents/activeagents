import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function SafeAgreementsContent({ safe_agreements, summary, investors }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const [filterStatus, setFilterStatus] = useState('')

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const statusColors = {
    draft: { bg: '#6b7280', text: '#ffffff' },
    sent: { bg: '#f59e0b', text: '#ffffff' },
    signed: { bg: '#22c55e', text: '#ffffff' },
    converted: { bg: '#3b82f6', text: '#ffffff' },
    cancelled: { bg: '#ef4444', text: '#ffffff' }
  }

  const formatCurrency = (amount) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 0 }).format(amount || 0)

  const filteredSafes = filterStatus ? safe_agreements.filter(s => s.status === filterStatus) : safe_agreements

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '32px' }}>
      <div style={{ position: 'fixed', top: '16px', right: '16px', zIndex: 50 }}>
        <button onClick={toggleDarkMode} style={{ padding: '8px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', border: 'none', cursor: 'pointer' }}>{darkMode ? '☀️' : '🌙'}</button>
      </div>

      <div style={{ maxWidth: '1280px', margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
          <div>
            <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, margin: 0 }}>SAFE Agreements</h1>
            <p style={{ color: colors.textSecondary, marginTop: '4px' }}>Track and manage investor SAFEs</p>
          </div>
          <button onClick={() => router.visit('/admin/safe_agreements/new')} style={{ padding: '10px 20px', backgroundColor: '#FA343B', color: 'white', border: 'none', borderRadius: '8px', fontWeight: '600', cursor: 'pointer' }}>+ New SAFE</button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '32px' }}>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Total Committed</div>
            <div style={{ color: colors.textPrimary, fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>{formatCurrency(summary.total_amount)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Signed Amount</div>
            <div style={{ color: '#22c55e', fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>{formatCurrency(summary.signed_amount)}</div>
          </div>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px' }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Pending Signature</div>
            <div style={{ color: '#f59e0b', fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>{summary.by_status?.sent || 0}</div>
          </div>
        </div>

        <div style={{ marginBottom: '24px', display: 'flex', gap: '8px' }}>
          {['', 'draft', 'sent', 'signed', 'converted'].map(status => (
            <button key={status} onClick={() => setFilterStatus(status)} style={{ padding: '8px 16px', borderRadius: '6px', border: `1px solid ${colors.border}`, backgroundColor: filterStatus === status ? '#FA343B' : colors.cardBg, color: filterStatus === status ? 'white' : colors.textSecondary, cursor: 'pointer', textTransform: 'capitalize' }}>
              {status || 'All'}
            </button>
          ))}
        </div>

        <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', overflow: 'hidden' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Investor</th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Amount</th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Val Cap</th>
                <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Type</th>
                <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {filteredSafes.map(safe => (
                <tr key={safe.id} onClick={() => router.visit(`/admin/safe_agreements/${safe.id}`)} style={{ borderBottom: `1px solid ${colors.border}`, cursor: 'pointer' }}>
                  <td style={{ padding: '16px', color: colors.textPrimary, fontWeight: '500' }}>{safe.investor_name}</td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textPrimary, fontWeight: '600' }}>{formatCurrency(safe.investment_amount)}</td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary }}>{safe.valuation_cap ? formatCurrency(safe.valuation_cap) : 'MFN'}</td>
                  <td style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, textTransform: 'capitalize' }}>{safe.safe_type.replace('_', ' ')}</td>
                  <td style={{ padding: '16px', textAlign: 'center' }}>
                    <span style={{ padding: '4px 8px', borderRadius: '4px', backgroundColor: statusColors[safe.status]?.bg, color: statusColors[safe.status]?.text, fontSize: '12px', fontWeight: '500' }}>{safe.display_status}</span>
                  </td>
                </tr>
              ))}
              {filteredSafes.length === 0 && (
                <tr><td colSpan="5" style={{ padding: '48px', textAlign: 'center', color: colors.textSecondary }}>No SAFE agreements yet</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

export default function SafeAgreementsIndex(props) {
  return (
    <ThemeProvider>
      <SafeAgreementsContent {...props} />
    </ThemeProvider>
  )
}
