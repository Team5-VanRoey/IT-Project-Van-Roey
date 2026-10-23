import { describe, expect, it } from 'vitest'
import { loginRequest, msalConfig } from '../../src/auth/authConfig'

describe('authConfig', () => {
  it('uses this site as redirect URI and keeps tokens in sessionStorage', () => {
    expect(msalConfig.auth.redirectUri).toBe(window.location.origin)
    expect(msalConfig.auth.authority).toMatch(/^https:\/\/login\.microsoftonline\.com\//)
    expect(msalConfig.cache?.cacheLocation).toBe('sessionStorage')
  })

  it('requests exactly one API scope at login', () => {
    expect(loginRequest.scopes).toHaveLength(1)
  })
})
