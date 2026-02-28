import React, { useState } from 'react'
import { router } from '@inertiajs/react'
import { ThemeProvider, useTheme } from '../../../contexts/ThemeContext'

function InvestorFormContent({ investor, investor_types, errors }) {
  const { darkMode, toggleDarkMode } = useTheme()
  const isEditing = !!investor?.id

  const [formData, setFormData] = useState({
    name: investor?.name || '',
    email: investor?.email || '',
    legal_name: investor?.legal_name || '',
    phone: investor?.phone || '',
    investor_type: investor?.investor_type || 'individual',
    entity_name: investor?.entity_name || '',
    entity_type: investor?.entity_type || '',
    address_line1: investor?.address?.line1 || '',
    address_line2: investor?.address?.line2 || '',
    city: investor?.address?.city || '',
    state: investor?.address?.state || '',
    postal_code: investor?.address?.postal_code || '',
    country: investor?.address?.country || 'US',
    portal_enabled: investor?.portal_enabled ?? true,
  })

  const colors = {
    bg: darkMode ? '#0f0f0f' : '#f9fafb',
    cardBg: darkMode ? '#1a1a1a' : '#ffffff',
    border: darkMode ? '#2a2a2a' : '#e5e7eb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    inputBg: darkMode ? '#252525' : '#ffffff',
    error: '#ef4444',
  }

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }))
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    if (isEditing) {
      router.put(`/admin/investors/${investor.id}`, { investor: formData })
    } else {
      router.post('/admin/investors', { investor: formData })
    }
  }

  const inputStyle = {
    width: '100%',
    padding: '10px 14px',
    backgroundColor: colors.inputBg,
    border: `1px solid ${colors.border}`,
    borderRadius: '8px',
    color: colors.textPrimary,
    fontSize: '14px',
    outline: 'none',
    boxSizing: 'border-box'
  }

  const labelStyle = {
    display: 'block',
    marginBottom: '6px',
    color: colors.textSecondary,
    fontSize: '14px',
    fontWeight: '500'
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

      <div style={{ maxWidth: '640px', margin: '0 auto' }}>
        {/* Back button */}
        <button
          onClick={() => router.visit(isEditing ? `/admin/investors/${investor.id}` : '/admin/investors')}
          style={{
            marginBottom: '24px',
            padding: '8px 16px',
            backgroundColor: 'transparent',
            border: `1px solid ${colors.border}`,
            borderRadius: '8px',
            color: colors.textSecondary,
            cursor: 'pointer'
          }}
        >
          ← Back
        </button>

        <h1 style={{ fontSize: '28px', fontWeight: '700', color: colors.textPrimary, marginBottom: '32px' }}>
          {isEditing ? 'Edit Investor' : 'Add Investor'}
        </h1>

        {errors && errors.length > 0 && (
          <div style={{
            backgroundColor: 'rgba(239, 68, 68, 0.1)',
            border: '1px solid #ef4444',
            borderRadius: '8px',
            padding: '16px',
            marginBottom: '24px'
          }}>
            <ul style={{ margin: 0, paddingLeft: '20px', color: colors.error }}>
              {errors.map((error, i) => <li key={i}>{error}</li>)}
            </ul>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          {/* Basic Info */}
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '24px',
            marginBottom: '24px'
          }}>
            <h2 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
              Basic Information
            </h2>

            <div style={{ display: 'grid', gap: '20px' }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div>
                  <label style={labelStyle}>Name *</label>
                  <input
                    type="text"
                    name="name"
                    value={formData.name}
                    onChange={handleChange}
                    required
                    style={inputStyle}
                    placeholder="John Smith"
                  />
                </div>
                <div>
                  <label style={labelStyle}>Email *</label>
                  <input
                    type="email"
                    name="email"
                    value={formData.email}
                    onChange={handleChange}
                    required
                    style={inputStyle}
                    placeholder="john@example.com"
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div>
                  <label style={labelStyle}>Legal Name</label>
                  <input
                    type="text"
                    name="legal_name"
                    value={formData.legal_name}
                    onChange={handleChange}
                    style={inputStyle}
                    placeholder="Full legal name"
                  />
                </div>
                <div>
                  <label style={labelStyle}>Phone</label>
                  <input
                    type="tel"
                    name="phone"
                    value={formData.phone}
                    onChange={handleChange}
                    style={inputStyle}
                    placeholder="+1 (555) 123-4567"
                  />
                </div>
              </div>

              <div>
                <label style={labelStyle}>Investor Type</label>
                <select
                  name="investor_type"
                  value={formData.investor_type}
                  onChange={handleChange}
                  style={inputStyle}
                >
                  <option value="individual">Individual</option>
                  <option value="entity">Entity</option>
                  <option value="trust">Trust</option>
                </select>
              </div>

              {(formData.investor_type === 'entity' || formData.investor_type === 'trust') && (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                  <div>
                    <label style={labelStyle}>Entity Name</label>
                    <input
                      type="text"
                      name="entity_name"
                      value={formData.entity_name}
                      onChange={handleChange}
                      style={inputStyle}
                      placeholder="ABC Holdings LLC"
                    />
                  </div>
                  <div>
                    <label style={labelStyle}>Entity Type</label>
                    <input
                      type="text"
                      name="entity_type"
                      value={formData.entity_type}
                      onChange={handleChange}
                      style={inputStyle}
                      placeholder="LLC, Corporation, Trust, etc."
                    />
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Address */}
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '24px',
            marginBottom: '24px'
          }}>
            <h2 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
              Address
            </h2>

            <div style={{ display: 'grid', gap: '20px' }}>
              <div>
                <label style={labelStyle}>Address Line 1</label>
                <input
                  type="text"
                  name="address_line1"
                  value={formData.address_line1}
                  onChange={handleChange}
                  style={inputStyle}
                  placeholder="123 Main St"
                />
              </div>
              <div>
                <label style={labelStyle}>Address Line 2</label>
                <input
                  type="text"
                  name="address_line2"
                  value={formData.address_line2}
                  onChange={handleChange}
                  style={inputStyle}
                  placeholder="Suite 100"
                />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px' }}>
                <div>
                  <label style={labelStyle}>City</label>
                  <input
                    type="text"
                    name="city"
                    value={formData.city}
                    onChange={handleChange}
                    style={inputStyle}
                    placeholder="San Francisco"
                  />
                </div>
                <div>
                  <label style={labelStyle}>State</label>
                  <input
                    type="text"
                    name="state"
                    value={formData.state}
                    onChange={handleChange}
                    style={inputStyle}
                    placeholder="CA"
                  />
                </div>
                <div>
                  <label style={labelStyle}>Postal Code</label>
                  <input
                    type="text"
                    name="postal_code"
                    value={formData.postal_code}
                    onChange={handleChange}
                    style={inputStyle}
                    placeholder="94107"
                  />
                </div>
              </div>
              <div>
                <label style={labelStyle}>Country</label>
                <input
                  type="text"
                  name="country"
                  value={formData.country}
                  onChange={handleChange}
                  style={inputStyle}
                  placeholder="US"
                />
              </div>
            </div>
          </div>

          {/* Portal Access */}
          <div style={{
            backgroundColor: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '12px',
            padding: '24px',
            marginBottom: '24px'
          }}>
            <h2 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '20px' }}>
              Portal Access
            </h2>

            <label style={{ display: 'flex', alignItems: 'center', gap: '12px', cursor: 'pointer' }}>
              <input
                type="checkbox"
                name="portal_enabled"
                checked={formData.portal_enabled}
                onChange={handleChange}
                style={{ width: '18px', height: '18px', accentColor: '#FA343B' }}
              />
              <span style={{ color: colors.textPrimary }}>Enable investor portal access</span>
            </label>
            <p style={{ color: colors.textSecondary, fontSize: '14px', marginTop: '8px', marginLeft: '30px' }}>
              When enabled, you can send this investor a magic link to access their portal.
            </p>
          </div>

          {/* Submit */}
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
            <button
              type="button"
              onClick={() => router.visit(isEditing ? `/admin/investors/${investor.id}` : '/admin/investors')}
              style={{
                padding: '12px 24px',
                backgroundColor: 'transparent',
                border: `1px solid ${colors.border}`,
                borderRadius: '8px',
                color: colors.textSecondary,
                fontWeight: '600',
                cursor: 'pointer'
              }}
            >
              Cancel
            </button>
            <button
              type="submit"
              style={{
                padding: '12px 24px',
                backgroundColor: '#FA343B',
                border: 'none',
                borderRadius: '8px',
                color: 'white',
                fontWeight: '600',
                cursor: 'pointer'
              }}
            >
              {isEditing ? 'Save Changes' : 'Add Investor'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

export default function InvestorForm(props) {
  return (
    <ThemeProvider>
      <InvestorFormContent {...props} />
    </ThemeProvider>
  )
}
