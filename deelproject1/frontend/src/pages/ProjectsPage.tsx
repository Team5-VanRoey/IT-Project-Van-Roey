import { useEffect, useState } from 'react'
import './ProjectsPage.css'

type Snapshot = {
  uploadedAt: string
  fileName: string
  projects: { id: string; columns: Record<string, string> }[]
}

// Shows the projects of the newest uploaded SharePoint project list
function ProjectsPage() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // ponytail: loads every snapshot and keeps the newest (API sorts newest first), add a /latest endpoint when the history grows
    fetch('/api/projectlists')
      .then(async (response) => {
        if (!response.ok) throw new Error()
        const snapshots: Snapshot[] = await response.json()
        setSnapshot(snapshots[0] ?? null)
      })
      .catch(() => setError('De projecten konden niet geladen worden.'))
      .finally(() => setIsLoading(false))
  }, [])

  const headers = Object.keys(snapshot?.projects[0]?.columns ?? {})

  return (
    <>
      <h1>Projecten</h1>

      {isLoading && <p>Projecten laden…</p>}
      {error && (
        <p className="projects-error" role="alert">
          {error}
        </p>
      )}
      {!isLoading && !error && !snapshot && <p>Nog geen projectenlijst opgeladen. Doe dit via het Dashboard.</p>}

      {snapshot && (
        <>
          <p>
            {snapshot.projects.length} project(en) uit <strong>{snapshot.fileName}</strong>, opgeladen op{' '}
            {new Date(snapshot.uploadedAt).toLocaleString('nl-BE')}.
          </p>

          {headers.length === 0 && <p>Deze upload bevat geen kolomgegevens. Laad de export opnieuw op.</p>}

          <div className="projects-table" hidden={headers.length === 0}>
            <table>
              <thead>
                <tr>
                  {headers.map((header) => (
                    <th key={header}>{header}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {snapshot.projects.map((project) => (
                  <tr key={project.id}>
                    {headers.map((header) => (
                      <td key={header}>{project.columns[header] || '—'}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </>
  )
}

export default ProjectsPage
