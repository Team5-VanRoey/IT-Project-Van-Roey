import { useState } from 'react'
import EntraTestPanel from '../components/EntraTestPanel'
import ProjectListUpload from '../components/ProjectListUpload'
import Sidebar from '../components/Sidebar'
import ProjectsPage from './ProjectsPage'
import './DashboardPage.css'

type DashboardPageProps = {
  onLogout: () => void
}

function DashboardPage({ onLogout }: DashboardPageProps) {
  const [activePage, setActivePage] = useState('Dashboard')

  return (
    <div className="dashboard-page">
      <Sidebar activeItem={activePage} onSelect={setActivePage} onLogout={onLogout} />

      <main className="dashboard-content">
        {activePage === 'Projecten' ? (
          <ProjectsPage />
        ) : (
          <>
            <h1>Dashboard</h1>
            <p>Hier komt het overzicht van je projecten.</p>

            <ProjectListUpload onShowProjects={() => setActivePage('Projecten')} />

            {import.meta.env.DEV && <EntraTestPanel />}
          </>
        )}
      </main>
    </div>
  )
}

export default DashboardPage
