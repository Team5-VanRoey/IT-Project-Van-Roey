import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { resetMsal } from '../test/msal'
import DashboardPage from './DashboardPage'

describe('DashboardPage', () => {
  beforeEach(resetMsal)

  it('shows the sidebar, the dashboard and (in development) the Entra test panel', () => {
    render(<DashboardPage onLogout={vi.fn()} />)

    expect(screen.getByRole('navigation')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /entra id test/i })).toBeInTheDocument()
  })
})
