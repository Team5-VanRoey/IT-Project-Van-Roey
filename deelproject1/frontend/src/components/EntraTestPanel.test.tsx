import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { InteractionRequiredAuthError } from '@azure/msal-browser'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { msal, resetMsal } from '../test/msal'
import EntraTestPanel from './EntraTestPanel'

const account = { name: 'Test User', username: 'test@vanroey.be' }

function signIn() {
  msal.accounts = [account]
  msal.instance.acquireTokenSilent.mockResolvedValue({ accessToken: 'test-token' })
}

describe('EntraTestPanel', () => {
  beforeEach(resetMsal)
  afterEach(() => vi.unstubAllGlobals())

  it('says when nobody is signed in with Microsoft', () => {
    render(<EntraTestPanel />)

    expect(screen.getByText(/niet aangemeld met microsoft/i)).toBeInTheDocument()
    expect(screen.queryByRole('button')).not.toBeInTheDocument()
  })

  it('calls GET /api/me with the access token and shows the result', async () => {
    signIn()
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ name: 'Test User' }) })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    render(<EntraTestPanel />)

    expect(screen.getByText('Test User')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /api\/me/i }))

    expect(fetchMock).toHaveBeenCalledWith('/api/me', { headers: { Authorization: 'Bearer test-token' } })
    expect(await screen.findByText(/"name": "Test User"/)).toBeInTheDocument()
  })

  it('shows the HTTP status when the API refuses', async () => {
    signIn()
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 401, statusText: 'Unauthorized' }))
    const user = userEvent.setup()
    render(<EntraTestPanel />)

    await user.click(screen.getByRole('button', { name: /api\/me/i }))

    expect(await screen.findByText('API gaf 401 Unauthorized')).toBeInTheDocument()
  })

  it('redirects to Microsoft when the token needs interaction', async () => {
    signIn()
    msal.instance.acquireTokenSilent.mockRejectedValue(new InteractionRequiredAuthError('interaction_required', 'Interaction required'))
    const user = userEvent.setup()
    render(<EntraTestPanel />)

    await user.click(screen.getByRole('button', { name: /api\/me/i }))

    expect(msal.instance.acquireTokenRedirect).toHaveBeenCalledWith(expect.objectContaining({ account }))
  })

  it('shows other errors', async () => {
    signIn()
    msal.instance.acquireTokenSilent.mockRejectedValue(new Error('network down'))
    const user = userEvent.setup()
    render(<EntraTestPanel />)

    await user.click(screen.getByRole('button', { name: /api\/me/i }))

    expect(await screen.findByText('Error: network down')).toBeInTheDocument()
  })
})
