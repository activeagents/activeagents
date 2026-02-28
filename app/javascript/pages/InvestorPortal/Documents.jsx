import React from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../contexts/ThemeContext'

function DocumentsContent({ investor, company, documents }) {
  const { darkMode, toggleDarkMode } = useTheme()

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const formatBytes = (bytes) => {
    if (!bytes) return ''
    const k = 1024
    if (bytes < k) return `${bytes} B`
    if (bytes < k * k) return `${(bytes / k).toFixed(1)} KB`
    return `${(bytes / (k * k)).toFixed(1)} MB`
  }

  const formatDate = (dateString) => dateString ? new Date(dateString).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : ''

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
          </div>
        </div>
      </header>

      <main style={{ maxWidth: '1280px', margin: '0 auto', padding: '32px' }}>
        <button onClick={() => router.visit('/investor/dashboard')} style={{ marginBottom: '24px', padding: '8px 16px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textSecondary, cursor: 'pointer' }}>← Back to Dashboard</button>

        <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, marginBottom: '8px' }}>Documents</h1>
        <p style={{ color: colors.textSecondary, marginBottom: '32px' }}>Access pitch decks, investment documents, and company updates.</p>

        {documents.length > 0 ? (
          <div style={{ display: 'grid', gap: '16px' }}>
            {documents.map(doc => (
              <div
                key={doc.id}
                style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '16px', flex: 1 }}>
                  <div style={{ width: '48px', height: '48px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '20px' }}>
                    📄
                  </div>
                  <div>
                    <div style={{ color: colors.textPrimary, fontWeight: '600' }}>{doc.name}</div>
                    <div style={{ color: colors.textSecondary, fontSize: '14px' }}>
                      {doc.document_type_label}
                      {doc.version && ` • v${doc.version}`}
                      {doc.file && ` • ${formatBytes(doc.file.byte_size)}`}
                      {doc.created_at && ` • ${formatDate(doc.created_at)}`}
                    </div>
                    {doc.description && <div style={{ color: colors.textSecondary, fontSize: '14px', marginTop: '4px' }}>{doc.description}</div>}
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '12px' }}>
                  <button
                    onClick={() => router.visit(`/investor/documents/${doc.id}`)}
                    style={{ padding: '8px 16px', backgroundColor: '#FA343B', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: '500' }}
                  >
                    View
                  </button>
                  <button
                    onClick={() => window.location.href = `/investor/documents/${doc.id}/download`}
                    style={{ padding: '8px 16px', backgroundColor: 'transparent', color: colors.textPrimary, border: `1px solid ${colors.border}`, borderRadius: '6px', cursor: 'pointer', fontWeight: '500' }}
                  >
                    Download
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '48px', textAlign: 'center' }}>
            <div style={{ fontSize: '48px', marginBottom: '16px' }}>📁</div>
            <p style={{ color: colors.textSecondary }}>No documents have been shared with you yet.</p>
          </div>
        )}
      </main>
    </div>
  )
}

export default function Documents(props) {
  return (
    <ThemeProvider>
      <DocumentsContent {...props} />
    </ThemeProvider>
  )
}
