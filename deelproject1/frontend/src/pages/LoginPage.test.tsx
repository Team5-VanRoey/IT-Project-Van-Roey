import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import LoginPage from './LoginPage'

describe('LoginPage', () => {
  it('calls onLogin with the Microsoft button', async () => {
    const onLogin = vi.fn()
    const user = userEvent.setup()
    render(<LoginPage onLogin={onLogin} onSkipLogin={vi.fn()} />)

    await user.click(screen.getByRole('button', { name: /aanmelden met microsoft/i }))

    expect(onLogin).toHaveBeenCalledOnce()
    expect(screen.getByRole('img', { name: 'VanRoey' })).toBeInTheDocument()
  })

  it('calls onSkipLogin with the dev button (only in development)', async () => {
    const onSkipLogin = vi.fn()
    const user = userEvent.setup()
    render(<LoginPage onLogin={vi.fn()} onSkipLogin={onSkipLogin} />)

    await user.click(screen.getByRole('button', { name: /ga naar dashboard/i }))

    expect(onSkipLogin).toHaveBeenCalledOnce()
  })
})
