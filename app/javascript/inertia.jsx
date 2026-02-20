import React from 'react'
import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

// Explicitly import pages since we're using esbuild (not Vite)
import Dashboard from './pages/Dashboard'
import PlansIndex from './pages/Plans/Index'
import SubscriptionsIndex from './pages/Subscriptions/Index'

const pages = {
  'Dashboard': Dashboard,
  'Plans/Index': PlansIndex,
  'Subscriptions/Index': SubscriptionsIndex,
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
