import React, { useState, useRef } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function DocumentFormContent({ document, document_types, safe_agreements, errors }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const isEditing = !!document?.id
  const fileInputRef = useRef(null)

  const [formData, setFormData] = useState({
    name: document?.name || '',
    document_type: document?.document_type || 'pitch_deck',
    description: document?.description || '',
    version: document?.version || '',
    public_to_all_investors: document?.public_to_all_investors ?? false,
    requires_accreditation: document?.requires_accreditation ?? false,
    safe_agreement_id: document?.safe_agreement_id || '',
  })
  const [selectedFile, setSelectedFile] = useState(null)

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    inputBg: darkMode ? '#252525' : '#ffffff',
  }

  const typeLabels = {
    ppm: 'Private Placement Memorandum',
    pitch_deck: 'Pitch Deck',
    safe: 'SAFE Agreement',
    side_letter: 'Side Letter',
    cap_table: 'Cap Table',
    other: 'Other Document'
  }

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target
    setFormData(prev => ({ ...prev, [name]: type === 'checkbox' ? checked : value }))
  }

  const handleFileChange = (e) => {
    setSelectedFile(e.target.files[0])
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    const data = new FormData()
    Object.entries(formData).forEach(([key, value]) => {
      data.append(`investor_document[${key}]`, value)
    })
    if (selectedFile) {
      data.append('investor_document[file]', selectedFile)
    }

    if (isEditing) {
      router.post(`/admin/investor_documents/${document.id}`, data, { forceFormData: true, _method: 'put' })
    } else {
      router.post('/admin/investor_documents', data, { forceFormData: true })
    }
  }

  const inputStyle = { width: '100%', padding: '10px 14px', backgroundColor: colors.inputBg, border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textPrimary, fontSize: '14px', boxSizing: 'border-box' }
  const labelStyle = { display: 'block', marginBottom: '6px', color: colors.textSecondary, fontSize: '14px', fontWeight: '500' }

  return (
    <div style={{ minHeight: '100vh', backgroundColor: colors.bg, padding: '32px' }}>
      <div style={{ position: 'fixed', top: '16px', right: '16px', zIndex: 50 }}>
        <button onClick={toggleDarkMode} style={{ padding: '8px', borderRadius: '8px', backgroundColor: darkMode ? '#252525' : '#f3f4f6', border: 'none', cursor: 'pointer' }}>{darkMode ? '☀️' : '🌙'}</button>
      </div>

      <div style={{ maxWidth: '640px', margin: '0 auto' }}>
        <button onClick={() => router.visit('/admin/investor_documents')} style={{ marginBottom: '24px', padding: '8px 16px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textSecondary, cursor: 'pointer' }}>← Back</button>

        <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, marginBottom: '32px' }}>
          {isEditing ? 'Edit Document' : 'Upload Document'}
        </h1>

        {errors?.length > 0 && (
          <div style={{ backgroundColor: 'rgba(239, 68, 68, 0.1)', border: '1px solid #ef4444', borderRadius: '8px', padding: '16px', marginBottom: '24px' }}>
            <ul style={{ margin: 0, paddingLeft: '20px', color: '#ef4444' }}>{errors.map((e, i) => <li key={i}>{e}</li>)}</ul>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
            <div style={{ marginBottom: '20px' }}>
              <label style={labelStyle}>Document Name *</label>
              <input type="text" name="name" value={formData.name} onChange={handleChange} required style={inputStyle} placeholder="Q4 2024 Pitch Deck" />
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label style={labelStyle}>Document Type *</label>
              <select name="document_type" value={formData.document_type} onChange={handleChange} style={inputStyle}>
                {document_types.map(type => <option key={type} value={type}>{typeLabels[type]}</option>)}
              </select>
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label style={labelStyle}>Description</label>
              <textarea name="description" value={formData.description} onChange={handleChange} rows={3} style={inputStyle} placeholder="Optional description..." />
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label style={labelStyle}>Version</label>
              <input type="text" name="version" value={formData.version} onChange={handleChange} style={inputStyle} placeholder="1.0" />
            </div>

            {!isEditing && (
              <div style={{ marginBottom: '20px' }}>
                <label style={labelStyle}>File *</label>
                <input type="file" ref={fileInputRef} onChange={handleFileChange} accept=".pdf,.doc,.docx,.ppt,.pptx" style={{ color: colors.textPrimary }} />
                <p style={{ color: colors.textSecondary, fontSize: '12px', marginTop: '4px' }}>PDF, Word, or PowerPoint files up to 50MB</p>
              </div>
            )}
          </div>

          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
            <h2 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>Access Settings</h2>

            <label style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px', cursor: 'pointer' }}>
              <input type="checkbox" name="public_to_all_investors" checked={formData.public_to_all_investors} onChange={handleChange} style={{ width: '18px', height: '18px', accentColor: '#FA343B' }} />
              <span style={{ color: colors.textPrimary }}>Make public to all investors</span>
            </label>
            <p style={{ color: colors.textSecondary, fontSize: '14px', marginLeft: '30px', marginBottom: '16px' }}>All investors with portal access will be able to view this document.</p>

            <label style={{ display: 'flex', alignItems: 'center', gap: '12px', cursor: 'pointer' }}>
              <input type="checkbox" name="requires_accreditation" checked={formData.requires_accreditation} onChange={handleChange} style={{ width: '18px', height: '18px', accentColor: '#FA343B' }} />
              <span style={{ color: colors.textPrimary }}>Requires accreditation</span>
            </label>
          </div>

          <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
            <button type="button" onClick={() => router.visit('/admin/investor_documents')} style={{ padding: '12px 24px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textSecondary, fontWeight: '600', cursor: 'pointer' }}>Cancel</button>
            <button type="submit" style={{ padding: '12px 24px', backgroundColor: '#FA343B', border: 'none', borderRadius: '8px', color: 'white', fontWeight: '600', cursor: 'pointer' }}>{isEditing ? 'Save Changes' : 'Upload Document'}</button>
          </div>
        </form>
      </div>
    </div>
  )
}

export default function DocumentForm(props) {
  return (
    <ThemeProvider>
      <DocumentFormContent {...props} />
    </ThemeProvider>
  )
}
