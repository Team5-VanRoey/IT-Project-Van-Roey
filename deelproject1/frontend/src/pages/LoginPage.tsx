import './LoginPage.css'

function MicrosoftIcon() {
  return (
    <svg className="microsoft-icon" viewBox="0 0 20 20" aria-hidden="true">
      <rect x="0" y="0" width="9" height="9" />
      <rect x="11" y="0" width="9" height="9" />
      <rect x="0" y="11" width="9" height="9" />
      <rect x="11" y="11" width="9" height="9" />
    </svg>
  )
}

function InfoIcon() {
  return (
    <svg className="info-icon" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="8" r="7" />
      <line x1="8" y1="7" x2="8" y2="11.5" />
      <circle cx="8" cy="4.75" r="0.5" />
    </svg>
  )
}

type LoginPageProps = {
  onSkipLogin: () => void
}

function LoginPage({ onSkipLogin }: LoginPageProps) {
  return (
    <div className="login-page">
      <section className="login-hero">
        <img className="brand-logo" src="/VanRoey-Logo.svg" alt="VanRoey" />

        <div className="hero-content">
          <span className="hero-badge">Intern platform</span>
          <h1 className="hero-title">
            Van projectdata
            <br />
            naar duidelijke actie.
          </h1>
          <p className="hero-text">
            Volg projecten op, zet gesprekken om in deliverables en neem beslissingen op basis van
            betrouwbare AI-inzichten.
          </p>
        </div>

        <div className="hero-rings" aria-hidden="true" />
      </section>

      <section className="login-panel">
        <div className="login-card">
          <p className="login-eyebrow">Welkom terug</p>
          <h2 className="login-title">Aanmelden</h2>
          <p className="login-text">Gebruik je zakelijke Microsoft-account om verder te gaan.</p>

          <button type="button" className="microsoft-button">
            <MicrosoftIcon />
            Aanmelden met Microsoft
          </button>

          <div className="login-info">
            <InfoIcon />
            Je gebruikersrol en toegangsrechten worden automatisch bepaald.
          </div>

          {import.meta.env.DEV && (
            <button type="button" className="dev-button" onClick={onSkipLogin}>
              <span className="dev-pill">Dev</span>
              Ga naar dashboard
            </button>
          )}
        </div>
      </section>
    </div>
  )
}

export default LoginPage
