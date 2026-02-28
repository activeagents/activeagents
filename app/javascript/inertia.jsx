import React from 'react'
import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

// Explicitly import pages since we're using esbuild (not Vite)
import Dashboard from './pages/Dashboard'
import PlansIndex from './pages/Plans/Index'
import SubscriptionsIndex from './pages/Subscriptions/Index'

// Admin - Investors
import AdminInvestorsIndex from './pages/Admin/Investors/Index'
import AdminInvestorsShow from './pages/Admin/Investors/Show'
import AdminInvestorsForm from './pages/Admin/Investors/Form'

// Admin - Documents
import AdminDocumentsIndex from './pages/Admin/Documents/Index'
import AdminDocumentsForm from './pages/Admin/Documents/Form'

// Admin - SAFE Agreements
import AdminSafeAgreementsIndex from './pages/Admin/SafeAgreements/Index'
import AdminSafeAgreementsForm from './pages/Admin/SafeAgreements/Form'

// Admin - Cap Table
import AdminCapTableIndex from './pages/Admin/CapTable/Index'

// Investor Portal
import InvestorPortalLogin from './pages/InvestorPortal/Login'
import InvestorPortalDashboard from './pages/InvestorPortal/Dashboard'
import InvestorPortalDocuments from './pages/InvestorPortal/Documents'

const pages = {
  'Dashboard': Dashboard,
  'Plans/Index': PlansIndex,
  'Subscriptions/Index': SubscriptionsIndex,
  // Admin - Investors
  'Admin/Investors/Index': AdminInvestorsIndex,
  'Admin/Investors/Show': AdminInvestorsShow,
  'Admin/Investors/Form': AdminInvestorsForm,
  // Admin - Documents
  'Admin/Documents/Index': AdminDocumentsIndex,
  'Admin/Documents/Form': AdminDocumentsForm,
  // Admin - SAFE Agreements
  'Admin/SafeAgreements/Index': AdminSafeAgreementsIndex,
  'Admin/SafeAgreements/Form': AdminSafeAgreementsForm,
  // Admin - Cap Table
  'Admin/CapTable/Index': AdminCapTableIndex,
  // Investor Portal
  'InvestorPortal/Login': InvestorPortalLogin,
  'InvestorPortal/Dashboard': InvestorPortalDashboard,
  'InvestorPortal/Documents': InvestorPortalDocuments,
}

createInertiaApp({
  resolve: name => {
    const page = pages[name]
    if (!page) {
      throw new Error(`Page not found: ${name}`)
    }
    return page
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
