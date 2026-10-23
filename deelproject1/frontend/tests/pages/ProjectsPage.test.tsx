import { render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import ProjectsPage from '../../src/pages/ProjectsPage'

function respondWith(snapshots: unknown[]) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => snapshots }))
}

describe('ProjectsPage', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('shows every column of the newest snapshot', async () => {
    respondWith([
      {
        uploadedAt: '2026-10-23T13:00:00Z',
        fileName: 'nieuw.xlsx',
        projects: [
          { id: '1', columns: { Klant: 'MrSolar', PM: 'Els', 'Geplande go-live': '2026-10-01' } },
          { id: '2', columns: { Klant: 'Dego', PM: 'Jan', 'Geplande go-live': '' } },
        ],
      },
      { uploadedAt: '2026-10-01T13:00:00Z', fileName: 'oud.xlsx', projects: [] },
    ])

    render(<ProjectsPage />)

    expect(await screen.findByText('MrSolar')).toBeInTheDocument()
    expect(screen.getByText('nieuw.xlsx')).toBeInTheDocument()
    expect(screen.getAllByRole('columnheader').map((th) => th.textContent)).toEqual(['Klant', 'PM', 'Geplande go-live'])
    expect(screen.getByText('2026-10-01')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
  })

  it('asks to upload again when the snapshot has no column data', async () => {
    respondWith([{ uploadedAt: '2026-10-23T13:00:00Z', fileName: 'oud.xlsx', projects: [{ id: '1', columns: {} }] }])

    render(<ProjectsPage />)

    expect(await screen.findByText(/geen kolomgegevens/i)).toBeInTheDocument()
  })

  it('says when nothing has been uploaded yet', async () => {
    respondWith([])

    render(<ProjectsPage />)

    expect(await screen.findByText(/nog geen projectenlijst opgeladen/i)).toBeInTheDocument()
  })

  it('shows an error when loading fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false }))

    render(<ProjectsPage />)

    expect(await screen.findByRole('alert')).toHaveTextContent('De projecten konden niet geladen worden.')
  })
})
