import { useState } from 'react'
import { InteractionRequiredAuthError } from '@azure/msal-browser'
import { useMsal } from '@azure/msal-react'
import { loginRequest } from '../auth/authConfig'
import './EntraTestPanel.css'

// Dev-only panel for the Entra ID spike (IT2627T05-172): shows the signed-in account
// and calls the protected GET /api/me with an access token.
function EntraTestPanel() {
  const { instance, accounts } = useMsal()
  const account = accounts[0]
  const [result, setResult] = useState<unknown>(null)
  const [error, setError] = useState<string | null>(null)

  const callApi = async () => {
    setError(null)
    setResult(null)
    const request = { ...loginRequest, account }

    try {
      const { accessToken } = await instance.acquireTokenSilent(request)
      const response = await fetch('/api/me', {
        headers: { Authorization: `Bearer ${accessToken}` },
      })

      if (!response.ok) {
        setError(`API gaf ${response.status} ${response.statusText}`)
        return
      }

      setResult(await response.json())
    } catch (e) {
      if (e instanceof InteractionRequiredAuthError) {
        await instance.acquireTokenRedirect(request)
        return
      }

      setError(String(e))
    }
  }

  return (
    <section className="entra-test">
      <h2>
        <span className="dev-pill">Dev</span> Entra ID test
      </h2>

      {account ? (
        <>
          <p>
            Aangemeld als <strong>{account.name}</strong> ({account.username})
          </p>
          <button type="button" className="entra-test-button" onClick={callApi}>
            Roep GET /api/me aan
          </button>
        </>
      ) : (
        <p>Niet aangemeld met Microsoft (dev-knop gebruikt).</p>
      )}

      {error && <p className="entra-test-error">{error}</p>}
      {result !== null && <pre>{JSON.stringify(result, null, 2)}</pre>}
    </section>
  )
}

export default EntraTestPanel
