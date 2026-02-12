export default function Dashboard({ user, account }) {
  return (
    <div className="min-h-screen bg-gray-100">
      <nav className="bg-white shadow">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 justify-between items-center">
            <div className="flex items-center">
              <span className="text-xl font-bold text-indigo-600">ActiveAgent</span>
            </div>
            <div className="flex items-center space-x-4">
              <a href="/plans" className="text-sm text-gray-600 hover:text-gray-900">Plans</a>
              <a href="/subscriptions" className="text-sm text-gray-600 hover:text-gray-900">Billing</a>
              <span className="text-sm text-gray-500">{user.email}</span>
              <form action="/session" method="post" style={{ display: 'inline' }}>
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="authenticity_token" value={document.querySelector('meta[name="csrf-token"]')?.content || ''} />
                <button type="submit" className="text-sm text-red-600 hover:text-red-800">Sign Out</button>
              </form>
            </div>
          </div>
        </div>
      </nav>

      <header className="bg-white shadow">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <h1 className="text-3xl font-bold tracking-tight text-gray-900">Dashboard</h1>
        </div>
      </header>

      <main>
        <div className="mx-auto max-w-7xl py-6 sm:px-6 lg:px-8">
          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3 px-4 sm:px-0">
            {/* User Card */}
            <div className="bg-white rounded-lg shadow p-6">
              <h3 className="text-sm font-medium text-gray-500 uppercase">User</h3>
              <p className="mt-2 text-xl font-semibold text-gray-900">{user.name}</p>
              <p className="text-sm text-gray-600">{user.email}</p>
            </div>

            {/* Account Card */}
            {account && (
              <div className="bg-white rounded-lg shadow p-6">
                <h3 className="text-sm font-medium text-gray-500 uppercase">Account</h3>
                <p className="mt-2 text-xl font-semibold text-gray-900">{account.name}</p>
                <div className="mt-2 flex items-center space-x-2">
                  <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                    account.subscribed
                      ? 'bg-green-100 text-green-800'
                      : account.on_trial
                      ? 'bg-blue-100 text-blue-800'
                      : 'bg-gray-100 text-gray-800'
                  }`}>
                    {account.subscribed ? 'Subscribed' : account.on_trial ? 'Trial' : 'Free'}
                  </span>
                </div>
              </div>
            )}

            {/* Plan Card */}
            {account && (
              <div className="bg-white rounded-lg shadow p-6">
                <h3 className="text-sm font-medium text-gray-500 uppercase">Current Plan</h3>
                <p className="mt-2 text-xl font-semibold text-gray-900">{account.plan || 'Free'}</p>
                <a
                  href="/subscriptions"
                  className="mt-4 inline-block text-sm text-indigo-600 hover:text-indigo-500"
                >
                  {account.subscribed ? 'Manage subscription' : 'Upgrade plan'}
                </a>
              </div>
            )}
          </div>

          <div className="mt-8 px-4 sm:px-0">
            <div className="rounded-lg border-4 border-dashed border-gray-200 p-8">
              <p className="text-gray-500">Welcome to ActiveAgent! Your AI-powered development assistant.</p>
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}
