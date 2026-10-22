import EntraTestPanel from '../components/EntraTestPanel'
import Sidebar from '../components/Sidebar'
import './DashboardPage.css'

type DashboardPageProps = {
  onLogout: () => void
}

function DashboardPage({ onLogout }: DashboardPageProps) {
  return (
    <div className="dashboard-page">
      <Sidebar onLogout={onLogout} />

      <main className="dashboard-content">
        <h1>Dashboard</h1>
        <p>Hier komt het overzicht van je projecten.</p>

        {import.meta.env.DEV && <EntraTestPanel />}
      </main>
    </div>
  )
}

export default DashboardPage
