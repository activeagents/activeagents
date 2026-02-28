import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function SafeFormContent({ safe_agreement, investors, selected_investor_id, safe_types, errors }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const isEditing = !!safe_agreement?.id

  const [formData, setFormData] = useState({
    investor_id: safe_agreement?.investor_id || selected_investor_id || '',
    investment_amount: safe_agreement?.investment_amount || '',
    valuation_cap: safe_agreement?.valuation_cap || '',
    discount_percent: safe_agreement?.discount_percent || '',
    safe_type: safe_agreement?.safe_type || 'post_money',
    pro_rata_rights: safe_agreement?.pro_rata_rights ?? false,
    atlas_safe_id: safe_agreement?.atlas_safe_id || '',
  })

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    inputBg: darkMode ? '#252525' : '#ffffff',
  }

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target
    setFormData(prev => ({ ...prev, [name]: type === 'checkbox' ? checked : value }))
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    if (isEditing) {
      router.put(`/admin/safe_agreements/${safe_agreement.id}`, { safe_agreement: formData })
    } else {
      router.post('/admin/safe_agreements', { safe_agreement: formData })
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
        <button onClick={() => router.visit('/admin/safe_agreements')} style={{ marginBottom: '24px', padding: '8px 16px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textSecondary, cursor: 'pointer' }}>← Back</button>

        <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, marginBottom: '32px' }}>
          {isEditing ? 'Edit SAFE' : 'New SAFE Agreement'}
        </h1>

        {errors?.length > 0 && (
          <div style={{ backgroundColor: 'rgba(239, 68, 68, 0.1)', border: '1px solid #ef4444', borderRadius: '8px', padding: '16px', marginBottom: '24px' }}>
            <ul style={{ margin: 0, paddingLeft: '20px', color: '#ef4444' }}>{errors.map((e, i) => <li key={i}>{e}</li>)}</ul>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
            <div style={{ marginBottom: '20px' }}>
              <label style={labelStyle}>Investor *</label>
              <select name="investor_id" value={formData.investor_id} onChange={handleChange} required style={inputStyle}>
                <option value="">Select an investor</option>
                {investors.map(inv => <option key={inv.id} value={inv.id}>{inv.name} ({inv.email})</option>)}
              </select>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginBottom: '20px' }}>
              <div>
                <label style={labelStyle}>Investment Amount *</label>
                <input type="number" name="investment_amount" value={formData.investment_amount} onChange={handleChange} required style={inputStyle} placeholder="50000" />
              </div>
              <div>
                <label style={labelStyle}>Valuation Cap</label>
                <input type="number" name="valuation_cap" value={formData.valuation_cap} onChange={handleChange} style={inputStyle} placeholder="10000000" />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginBottom: '20px' }}>
              <div>
                <label style={labelStyle}>Discount %</label>
                <input type="number" name="discount_percent" value={formData.discount_percent} onChange={handleChange} style={inputStyle} placeholder="20" step="0.01" />
              </div>
              <div>
                <label style={labelStyle}>SAFE Type</label>
                <select name="safe_type" value={formData.safe_type} onChange={handleChange} style={inputStyle}>
                  <option value="post_money">Post-Money</option>
                  <option value="pre_money">Pre-Money</option>
                  <option value="mfn">MFN</option>
                </select>
              </div>
            </div>

            <label style={{ display: 'flex', alignItems: 'center', gap: '12px', cursor: 'pointer' }}>
              <input type="checkbox" name="pro_rata_rights" checked={formData.pro_rata_rights} onChange={handleChange} style={{ width: '18px', height: '18px', accentColor: '#FA343B' }} />
              <span style={{ color: colors.textPrimary }}>Pro-rata rights</span>
            </label>
          </div>

          <div style={{ backgroundColor: colors.cardBg, border: `1px solid ${colors.border}`, borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
            <h2 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px' }}>Stripe Atlas Integration</h2>
            <div>
              <label style={labelStyle}>Atlas SAFE ID</label>
              <input type="text" name="atlas_safe_id" value={formData.atlas_safe_id} onChange={handleChange} style={inputStyle} placeholder="Optional - link to Atlas SAFE" />
              <p style={{ color: colors.textSecondary, fontSize: '12px', marginTop: '4px' }}>If you created this SAFE in Stripe Atlas, paste the ID here to link them.</p>
            </div>
          </div>

          <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
            <button type="button" onClick={() => router.visit('/admin/safe_agreements')} style={{ padding: '12px 24px', backgroundColor: 'transparent', border: `1px solid ${colors.border}`, borderRadius: '8px', color: colors.textSecondary, fontWeight: '600', cursor: 'pointer' }}>Cancel</button>
            <button type="submit" style={{ padding: '12px 24px', backgroundColor: '#FA343B', border: 'none', borderRadius: '8px', color: 'white', fontWeight: '600', cursor: 'pointer' }}>{isEditing ? 'Save Changes' : 'Create SAFE'}</button>
          </div>
        </form>
      </div>
    </div>
  )
}

export default function SafeForm(props) {
  return (
    <ThemeProvider>
      <SafeFormContent {...props} />
    </ThemeProvider>
  )
}
