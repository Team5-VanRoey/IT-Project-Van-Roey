import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import Sidebar from './Sidebar'

describe('Sidebar', () => {
  it('marks Dashboard as active by default and switches the active item', async () => {
    const user = userEvent.setup()
    render(<Sidebar onLogout={vi.fn()} />)

    expect(screen.getByRole('button', { name: 'Dashboard' })).toHaveClass('active')

    await user.click(screen.getByRole('button', { name: 'Projecten' }))

    expect(screen.getByRole('button', { name: 'Projecten' })).toHaveClass('active')
    expect(screen.getByRole('button', { name: 'Dashboard' })).not.toHaveClass('active')
  })

  it('collapses and expands the menu', async () => {
    const user = userEvent.setup()
    const { container } = render(<Sidebar onLogout={vi.fn()} />)

    await user.click(screen.getByRole('button', { name: 'Inklappen' }))

    expect(container.querySelector('nav')).toHaveClass('collapsed')
    expect(screen.queryByText('Dashboard')).not.toBeInTheDocument()
    expect(screen.getByTitle('Dashboard')).toBeInTheDocument()
    expect(screen.getByTitle('Afmelden')).toBeInTheDocument()

    await user.click(screen.getByTitle('Menu uitklappen'))

    expect(container.querySelector('nav')).not.toHaveClass('collapsed')
    expect(screen.getByText('Dashboard')).toBeInTheDocument()
  })

  it('calls onLogout', async () => {
    const onLogout = vi.fn()
    const user = userEvent.setup()
    render(<Sidebar onLogout={onLogout} />)

    await user.click(screen.getByRole('button', { name: 'Afmelden' }))

    expect(onLogout).toHaveBeenCalledOnce()
  })
})
