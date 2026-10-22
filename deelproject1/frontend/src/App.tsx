import { useState } from 'react'
import { useIsAuthenticated, useMsal } from '@azure/msal-react'
import { loginRequest } from './auth/authConfig'
import DashboardPage from './pages/DashboardPage'
import LoginPage from './pages/LoginPage'

function App() {
  const { instance } = useMsal()
  const isAuthenticated = useIsAuthenticated()
  const [showDashboard, setShowDashboard] = useState(false)

  const handleLogout = () => {
    if (isAuthenticated) {
      instance.logoutRedirect()
      return
    }

    setShowDashboard(false)
  }

  if (isAuthenticated || showDashboard) {
    return <DashboardPage onLogout={handleLogout} />
  }

  return (
    <LoginPage
      onLogin={() => instance.loginRedirect(loginRequest)}
      onSkipLogin={() => setShowDashboard(true)}
    />
  )
}

export default App
