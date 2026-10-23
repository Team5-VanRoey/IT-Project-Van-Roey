import { useState, type FormEvent } from 'react'
import './ProjectListUpload.css'

type ImportResult = {
  snapshot: { fileName: string; projects: unknown[] }
  warnings: string[]
}

type ProjectListUploadProps = {
  onShowProjects: () => void
}

// Uploads the SharePoint project list export (xlsx) to POST /api/projectlists (IT2627T05-125)
function ProjectListUpload({ onShowProjects }: ProjectListUploadProps) {
  const [file, setFile] = useState<File | null>(null)
  const [result, setResult] = useState<ImportResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [isUploading, setIsUploading] = useState(false)

  const upload = async (event: FormEvent) => {
    event.preventDefault()
    if (!file) return

    setError(null)
    setResult(null)
    setIsUploading(true)
    const body = new FormData()
    body.append('file', file)

    try {
      const response = await fetch('/api/projectlists', { method: 'POST', body })
      if (!response.ok) {
        const problem = await response.json().catch(() => null)
        setError(problem?.detail ?? `Upload mislukt (${response.status}).`)
        return
      }

      setResult(await response.json())
    } catch {
      setError('De server is niet bereikbaar.')
    } finally {
      setIsUploading(false)
    }
  }

  return (
    <section className="project-upload">
      <h2>Projectenlijst opladen</h2>

      <form onSubmit={upload}>
        <label>
          SharePoint-export (.xlsx)
          <input type="file" accept=".xlsx" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        </label>
        <button type="submit" disabled={!file || isUploading}>
          {isUploading ? 'Bezig…' : 'Opladen'}
        </button>
      </form>

      {error && (
        <p className="project-upload-error" role="alert">
          {error}
        </p>
      )}

      {result && (
        <div className="project-upload-success" role="status">
          <p>
            ✓ {result.snapshot.projects.length} project(en) ingeladen uit <strong>{result.snapshot.fileName}</strong>.
          </p>

          {result.warnings.length > 0 && (
            <ul className="project-upload-warnings">
              {result.warnings.map((warning) => (
                <li key={warning}>{warning}</li>
              ))}
            </ul>
          )}

          <button type="button" onClick={onShowProjects}>
            Bekijk projecten
          </button>
        </div>
      )}
    </section>
  )
}

export default ProjectListUpload
