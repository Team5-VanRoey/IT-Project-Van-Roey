import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resetMsal } from '../msal'
import DashboardPage from '../../src/pages/DashboardPage'

describe('DashboardPage', () => {
  beforeEach(resetMsal)
  afterEach(() => vi.unstubAllGlobals())

  it('shows the sidebar, the dashboard and (in development) the Entra test panel', () => {
    render(<DashboardPage onLogout={vi.fn()} />)

    expect(screen.getByRole('navigation')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /entra id test/i })).toBeInTheDocument()
  })

  it('switches to the projects page from the sidebar', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => [] }))
    const user = userEvent.setup()
    render(<DashboardPage onLogout={vi.fn()} />)

    await user.click(screen.getByRole('button', { name: 'Projecten' }))

    expect(screen.getByRole('heading', { name: 'Projecten' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Projecten' })).toHaveClass('active')
    expect(await screen.findByText(/nog geen projectenlijst opgeladen/i)).toBeInTheDocument()
  })
})
