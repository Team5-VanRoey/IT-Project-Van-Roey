import type { Configuration, RedirectRequest } from '@azure/msal-browser'

export const msalConfig: Configuration = {
  auth: {
    clientId: import.meta.env.VITE_ENTRA_SPA_CLIENT_ID,
    authority: `https://login.microsoftonline.com/${import.meta.env.VITE_ENTRA_TENANT_ID}`,
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
  },
}

// Requesting the API scope at login means consent and the first access token happen in one round trip
export const loginRequest: RedirectRequest = {
  scopes: [import.meta.env.VITE_API_SCOPE],
}
