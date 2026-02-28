import React from 'react'
import { ThemeProvider, useTheme } from '../../contexts/ThemeContext'

function LoginContent() {
  const { darkMode } = useTheme()

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '32px' }}>
      <div style={{ maxWidth: '400px', width: '100%', textAlign: 'center' }}>
        <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '16px', padding: '48px 32px' }}>
          <div style={{ fontSize: '48px', marginBottom: '24px' }}>🔐</div>
          <h1 style={{ fontSize: '24px', fontWeight: '700', color: colors.textPrimary, marginBottom: '16px' }}>
            Investor Portal
          </h1>
          <p style={{ color: colors.textSecondary, marginBottom: '32px', lineHeight: '1.6' }}>
            Access to this portal requires a magic link. If you're an investor, please check your email for an access link or contact the company to request one.
          </p>
          <div style={{ backgroundColor: darkMode ? '#252525' : '#f3f4f6', borderRadius: '8px', padding: '16px' }}>
            <p style={{ color: colors.textSecondary, fontSize: '14px', margin: 0 }}>
              Don't have a link? Contact the company directly to request investor portal access.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

export default function Login(props) {
  return (
    <ThemeProvider>
      <LoginContent {...props} />
    </ThemeProvider>
  )
}
