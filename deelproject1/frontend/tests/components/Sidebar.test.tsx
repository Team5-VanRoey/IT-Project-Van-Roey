import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import Sidebar from '../../src/components/Sidebar'

describe('Sidebar', () => {
  it('marks the active item and reports a selection', async () => {
    const onSelect = vi.fn()
    const user = userEvent.setup()
    render(<Sidebar activeItem="Dashboard" onSelect={onSelect} onLogout={vi.fn()} />)

    expect(screen.getByRole('button', { name: 'Dashboard' })).toHaveClass('active')
    expect(screen.getByRole('button', { name: 'Projecten' })).not.toHaveClass('active')

    await user.click(screen.getByRole('button', { name: 'Projecten' }))

    expect(onSelect).toHaveBeenCalledWith('Projecten')
  })

  it('collapses and expands the menu', async () => {
    const user = userEvent.setup()
    const { container } = render(<Sidebar activeItem="Dashboard" onSelect={vi.fn()} onLogout={vi.fn()} />)

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
    render(<Sidebar activeItem="Dashboard" onSelect={vi.fn()} onLogout={onLogout} />)

    await user.click(screen.getByRole('button', { name: 'Afmelden' }))

    expect(onLogout).toHaveBeenCalledOnce()
  })
})
