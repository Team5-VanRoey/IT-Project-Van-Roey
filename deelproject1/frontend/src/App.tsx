import { useState } from 'react'
import DashboardPage from './pages/DashboardPage'
import LoginPage from './pages/LoginPage'

function App() {
  const [showDashboard, setShowDashboard] = useState(false)

  if (showDashboard) {
    return <DashboardPage onLogout={() => setShowDashboard(false)} />
  }

  return <LoginPage onSkipLogin={() => setShowDashboard(true)} />
}

export default App
