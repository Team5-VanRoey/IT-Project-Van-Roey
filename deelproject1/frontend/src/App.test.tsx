import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it } from 'vitest'
import { msal, resetMsal } from './test/msal'
import App from './App'
import { loginRequest } from './auth/authConfig'

describe('App', () => {
  beforeEach(resetMsal)

  it('starts on the login page when nobody is signed in', () => {
    render(<App />)

    expect(screen.getByRole('heading', { name: 'Aanmelden' })).toBeInTheDocument()
  })

  it('signs in with Microsoft through a redirect', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /aanmelden met microsoft/i }))

    expect(msal.instance.loginRedirect).toHaveBeenCalledWith(loginRequest)
  })

  it('goes to the dashboard with the dev button and back on logout', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /ga naar dashboard/i }))
    expect(screen.getByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Afmelden' }))
    expect(screen.getByRole('heading', { name: 'Aanmelden' })).toBeInTheDocument()
    expect(msal.instance.logoutRedirect).not.toHaveBeenCalled()
  })

  it('shows the dashboard to a signed-in user and signs out through Microsoft', async () => {
    msal.isAuthenticated = true
    msal.accounts = [{ name: 'Test User', username: 'test@vanroey.be' }]
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Afmelden' }))
    expect(msal.instance.logoutRedirect).toHaveBeenCalledOnce()
  })
})
