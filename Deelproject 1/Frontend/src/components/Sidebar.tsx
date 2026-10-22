import { useState } from 'react'
import './Sidebar.css'

const menuItems = [
  { name: 'Dashboard', icon: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z' },
  { name: 'Projecten', icon: 'M3 6h6l2 2h10v11H3z' },
]

const logoutIcon = 'M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10'

function Icon({ path }: { path: string }) {
  return (
    <svg className="sidebar-icon" viewBox="0 0 24 24" aria-hidden="true">
      <path d={path} />
    </svg>
  )
}

type SidebarProps = {
  onLogout: () => void
}

function Sidebar({ onLogout }: SidebarProps) {
  const [isCollapsed, setIsCollapsed] = useState(false)
  const [activeItem, setActiveItem] = useState('Dashboard')

  return (
    <nav className={isCollapsed ? 'sidebar collapsed' : 'sidebar'}>
      <div className="sidebar-logo">
        {isCollapsed ? (
          <img src="/VanRoey-logo-small.png" alt="VanRoey" />
        ) : (
          <img className="sidebar-logo-full" src="/VanRoey-Logo.svg" alt="VanRoey" />
        )}
      </div>

      <ul className="sidebar-menu">
        {menuItems.map((item) => (
          <li key={item.name}>
            <button
              type="button"
              className={item.name === activeItem ? 'sidebar-item active' : 'sidebar-item'}
              title={isCollapsed ? item.name : undefined}
              onClick={() => setActiveItem(item.name)}
            >
              <Icon path={item.icon} />
              {!isCollapsed && <span>{item.name}</span>}
            </button>
          </li>
        ))}
      </ul>

      <button
        type="button"
        className="sidebar-item sidebar-toggle"
        title={isCollapsed ? 'Menu uitklappen' : undefined}
        onClick={() => setIsCollapsed(!isCollapsed)}
      >
        <Icon path={isCollapsed ? 'M9 6l6 6-6 6' : 'M15 6l-6 6 6 6'} />
        {!isCollapsed && <span>Inklappen</span>}
      </button>

      <button
        type="button"
        className="sidebar-item"
        title={isCollapsed ? 'Afmelden' : undefined}
        onClick={onLogout}
      >
        <Icon path={logoutIcon} />
        {!isCollapsed && <span>Afmelden</span>}
      </button>
    </nav>
  )
}

export default Sidebar
