import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function InvestorsContent({ investors, summary }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const [searchQuery, setSearchQuery] = useState('')

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    inputBg: darkMode ? '#252525' : '#ffffff',
  }

  const filteredInvestors = investors.filter(i =>
    i.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    i.email.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const formatCurrency = (amount) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(amount)
  }

  const formatDate = (dateString) => {
    if (!dateString) return 'Never'
    return new Date(dateString).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    })
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
        {/* Header */}
        <div style={{ marginBottom: '32px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, margin: 0 }}>
                Investors
              </h1>
              <p style={{ color: colors.textSecondary, marginTop: '4px' }}>
                Manage your investors and track investments
              </p>
            </div>
            <button
              onClick={() => router.visit('/admin/investors/new')}
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
              + Add Investor
            </button>
          </div>
        </div>

        {/* Summary Cards */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '32px' }}>
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '20px'
          }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Total Investors</div>
            <div style={{ color: colors.textPrimary, fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>
              {summary.total_investors}
            </div>
          </div>
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '20px'
          }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Total Invested</div>
            <div style={{ color: colors.textPrimary, fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>
              {formatCurrency(summary.total_invested)}
            </div>
          </div>
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '20px'
          }}>
            <div style={{ color: colors.textSecondary, fontSize: '14px' }}>Pending Signatures</div>
            <div style={{ color: summary.pending_signatures > 0 ? '#f59e0b' : colors.textPrimary, fontSize: '28px', fontWeight: '700', marginTop: '4px' }}>
              {summary.pending_signatures}
            </div>
          </div>
        </div>

        {/* Search */}
        <div style={{ marginBottom: '24px' }}>
          <input
            type="text"
            placeholder="Search investors..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{
              width: '300px',
              padding: '10px 16px',
              backgroundColor: colors.inputBg,
              border: `1px solid ${colors.border}`,
              borderRadius: '8px',
              color: colors.textPrimary,
              fontSize: '14px',
              outline: 'none'
            }}
          />
        </div>

        {/* Investors Table */}
        <div style={{
          backgroundColor: colors.cardBg,
          border: `1px solid ${colors.border}`,
          borderRadius: '12px',
          overflow: 'hidden'
        }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: `1px solid ${colors.border}` }}>
                <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  Investor
                </th>
                <th style={{ padding: '16px', textAlign: 'left', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  Type
                </th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  Invested
                </th>
                <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  SAFEs
                </th>
                <th style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  Portal
                </th>
                <th style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontWeight: '500', fontSize: '12px', textTransform: 'uppercase' }}>
                  Last Access
                </th>
              </tr>
            </thead>
            <tbody>
              {filteredInvestors.map((investor) => (
                <tr
                  key={investor.id}
                  onClick={() => router.visit(`/admin/investors/${investor.id}`)}
                  style={{
                    borderBottom: `1px solid ${colors.border}`,
                    cursor: 'pointer'
                  }}
                  onMouseEnter={(e) => e.currentTarget.style.backgroundColor = darkMode ? '#252525' : '#f9fafb'}
                  onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
                >
                  <td style={{ padding: '16px' }}>
                    <div style={{ color: colors.textPrimary, fontWeight: '500' }}>{investor.name}</div>
                    <div style={{ color: colors.textSecondary, fontSize: '14px' }}>{investor.email}</div>
                  </td>
                  <td style={{ padding: '16px' }}>
                    <span style={{
                      padding: '4px 8px',
                      borderRadius: '4px',
                      backgroundColor: darkMode ? '#374151' : '#e5e7eb',
                      color: colors.textSecondary,
                      fontSize: '12px',
                      textTransform: 'capitalize'
                    }}>
                      {investor.investor_type}
                    </span>
                  </td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textPrimary, fontWeight: '500' }}>
                    {formatCurrency(investor.total_invested)}
                  </td>
                  <td style={{ padding: '16px', textAlign: 'center', color: colors.textSecondary }}>
                    {investor.safe_count}
                  </td>
                  <td style={{ padding: '16px', textAlign: 'center' }}>
                    <span style={{
                      display: 'inline-block',
                      width: '8px',
                      height: '8px',
                      borderRadius: '50%',
                      backgroundColor: investor.portal_enabled ? '#22c55e' : '#ef4444'
                    }} />
                  </td>
                  <td style={{ padding: '16px', textAlign: 'right', color: colors.textSecondary, fontSize: '14px' }}>
                    {formatDate(investor.last_accessed_at)}
                  </td>
                </tr>
              ))}
              {filteredInvestors.length === 0 && (
                <tr>
                  <td colSpan="6" style={{ padding: '48px', textAlign: 'center', color: colors.textSecondary }}>
                    {searchQuery ? 'No investors match your search' : 'No investors yet. Add your first investor to get started.'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

export default function InvestorsIndex(props) {
  return (
    <ThemeProvider>
      <InvestorsContent {...props} />
    </ThemeProvider>
  )
}
