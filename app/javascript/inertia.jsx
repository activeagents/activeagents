import React from 'react'
import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

// Explicitly import pages since we're using esbuild (not Vite)
import Dashboard from './pages/Dashboard'

const pages = {
  'Dashboard': Dashboard,
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
