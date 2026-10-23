import { vi } from 'vitest'

// Test double for @azure/msal-react: no real Microsoft sign-in in unit tests.
// Each test sets msal.isAuthenticated / msal.accounts and checks the calls on msal.instance.
export const msal = {
  isAuthenticated: false,
  accounts: [] as { name?: string; username: string }[],
  instance: {
    loginRedirect: vi.fn(),
    logoutRedirect: vi.fn(),
    acquireTokenSilent: vi.fn(),
    acquireTokenRedirect: vi.fn(),
  },
}

export function resetMsal() {
  msal.isAuthenticated = false
  msal.accounts = []
  Object.values(msal.instance).forEach((fn) => fn.mockReset())
}

vi.mock('@azure/msal-react', () => ({
  useMsal: () => ({ instance: msal.instance, accounts: msal.accounts }),
  useIsAuthenticated: () => msal.isAuthenticated,
}))
