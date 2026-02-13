import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

import Dashboard from './pages/Dashboard'
import Playground from './pages/Playground'

const pages = {
  'Dashboard': Dashboard,
  'Playground': Playground,
}

createInertiaApp({
  resolve: name => {
    const page = pages[name]
    if (!page) {
      throw new Error(`Unknown page: ${name}`)
    }
    return page
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
