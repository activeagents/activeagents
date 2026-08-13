import React from 'react'
import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

// Explicitly import pages since we're using esbuild (not Vite).
// The dashboard is not here: it ships in the activeagent gem's engine, which
// serves and bundles it under its own mount.
import PlansIndex from './pages/Plans/Index'
import SubscriptionsIndex from './pages/Subscriptions/Index'
import AdminSpacesIndex from './pages/Admin/Spaces/Index'
import AdminSpacesShow from './pages/Admin/Spaces/Show'

const pages = {
  'Plans/Index': PlansIndex,
  'Subscriptions/Index': SubscriptionsIndex,
  'Admin/Spaces/Index': AdminSpacesIndex,
  'Admin/Spaces/Show': AdminSpacesShow,
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
