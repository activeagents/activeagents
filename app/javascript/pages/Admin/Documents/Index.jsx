import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function DocumentsContent({ documents, document_types }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const [filterType, setFilterType] = useState('')

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  }

  const filteredDocs = filterType
    ? documents.filter(d => d.document_type === filterType)
    : documents

  const formatBytes = (bytes) => {
    if (!bytes) return '0 KB'
    const k = 1024
    if (bytes < k) return `${bytes} B`
    if (bytes < k * k) return `${(bytes / k).toFixed(1)} KB`
    return `${(bytes / (k * k)).toFixed(1)} MB`
  }

  const typeLabels = {
    ppm: 'PPM',
    pitch_deck: 'Pitch Deck',
    safe: 'SAFE',
    side_letter: 'Side Letter',
    cap_table: 'Cap Table',
    other: 'Other'
  }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '32px' }}>
      <div style={{ position: 'fixed', top: '16px', right: '16px', zIndex: 50 }}>
        <button onClick={toggleDarkMode} style={{ padding: '8px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', color: darkMode ? '#fbbf24' : '#4b5563', border: 'none', cursor: 'pointer' }}>
          {darkMode ? '☀️' : '🌙'}
        </button>
      </div>

      <div style={{ maxWidth: '1280px', margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
          <div>
            <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, margin: 0 }}>Documents</h1>
            <p style={{ color: colors.textSecondary, marginTop: '4px' }}>Manage investor documents and pitch materials</p>
          </div>
          <button
            onClick={() => router.visit('/admin/investor_documents/new')}
            style={{ padding: '10px 20px', backgroundColor: '#FA343B', color: 'white', border: 'none', borderRadius: '8px', fontWeight: '600', cursor: 'pointer' }}
          >
            + Upload Document
          </button>
        </div>

        <div style={{ marginBottom: '24px', display: 'flex', gap: '8px' }}>
          <button onClick={() => setFilterType('')} style={{ padding: '8px 16px', borderRadius: '6px', border: `1px solid ${colors.border}`, backgroundColor: !filterType ? '#FA343B' : colors.cardBg, color: !filterType ? 'white' : colors.textSecondary, cursor: 'pointer' }}>
            All
          </button>
          {document_types.map(type => (
            <button key={type} onClick={() => setFilterType(type)} style={{ padding: '8px 16px', borderRadius: '6px', border: `1px solid ${colors.border}`, backgroundColor: filterType === type ? '#FA343B' : colors.cardBg, color: filterType === type ? 'white' : colors.textSecondary, cursor: 'pointer', textTransform: 'capitalize' }}>
              {typeLabels[type] || type}
            </button>
          ))}
        </div>

        <div style={{ display: 'grid', gap: '16px' }}>
          {filteredDocs.map(doc => (
            <div
              key={doc.id}
              onClick={() => router.visit(`/admin/investor_documents/${doc.id}`)}
              style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '20px', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <div style={{ width: '48px', height: '48px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '20px' }}>
                  📄
                </div>
                <div>
                  <div style={{ color: colors.textPrimary, fontWeight: '600' }}>{doc.name}</div>
                  <div style={{ color: colors.textSecondary, fontSize: '14px' }}>
                    {doc.document_type_label} {doc.version && `• v${doc.version}`} {doc.file && `• ${formatBytes(doc.file.byte_size)}`}
                  </div>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '24px' }}>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ color: colors.textSecondary, fontSize: '12px' }}>Views</div>
                  <div style={{ color: colors.textPrimary, fontWeight: '600' }}>{doc.view_count}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ color: colors.textSecondary, fontSize: '12px' }}>Downloads</div>
                  <div style={{ color: colors.textPrimary, fontWeight: '600' }}>{doc.download_count}</div>
                </div>
                {doc.public_to_all_investors && (
                  <span style={{ padding: '4px 8px', borderRadius: '4px', backgroundColor: '#22c55e', color: 'white', fontSize: '12px' }}>Public</span>
                )}
              </div>
            </div>
          ))}
          {filteredDocs.length === 0 && (
            <div style={{ textAlign: 'center', padding: '48px', color: colors.textSecondary }}>
              No documents yet. Upload your first document to share with investors.
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default function DocumentsIndex(props) {
  return (
    <ThemeProvider>
      <DocumentsContent {...props} />
    </ThemeProvider>
  )
}
