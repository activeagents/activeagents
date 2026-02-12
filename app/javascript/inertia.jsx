import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

import Dashboard from './pages/Dashboard.jsx'
import SignIn from './pages/Auth/SignIn.jsx'
import SignUp from './pages/Auth/SignUp.jsx'
import PlansIndex from './pages/Plans/Index.jsx'
import SubscriptionsIndex from './pages/Subscriptions/Index.jsx'

const pages = {
  'Dashboard': Dashboard,
  'Auth/SignIn': SignIn,
  'Auth/SignUp': SignUp,
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
