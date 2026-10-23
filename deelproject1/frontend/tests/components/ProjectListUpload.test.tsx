import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import ProjectListUpload from '../../src/components/ProjectListUpload'

const xlsx = new File(['x'], 'export.xlsx')

async function uploadFile(onShowProjects = vi.fn()) {
  const user = userEvent.setup()
  render(<ProjectListUpload onShowProjects={onShowProjects} />)
  await user.upload(screen.getByLabelText(/sharepoint-export/i), xlsx)
  await user.click(screen.getByRole('button', { name: 'Opladen' }))
  return user
}

describe('ProjectListUpload', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('disables the upload button until a file is chosen', () => {
    render(<ProjectListUpload onShowProjects={vi.fn()} />)

    expect(screen.getByRole('button', { name: 'Opladen' })).toBeDisabled()
  })

  it('posts the file, confirms the import with its warnings and links to the projects', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        snapshot: { fileName: 'export.xlsx', projects: [{}, {}] },
        warnings: ["Project 'Dego' (rij 3) heeft geen GoLive-datum."],
      }),
    })
    vi.stubGlobal('fetch', fetchMock)
    const onShowProjects = vi.fn()

    const user = await uploadFile(onShowProjects)

    const [url, options] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/projectlists')
    expect((options.body as FormData).get('file')).toBe(xlsx)
    expect(await screen.findByRole('status')).toHaveTextContent('2 project(en) ingeladen uit export.xlsx')
    expect(screen.getByText(/dego' \(rij 3\) heeft geen golive-datum/i)).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Bekijk projecten' }))
    expect(onShowProjects).toHaveBeenCalledOnce()
  })

  it('shows the error message from the API', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 400,
      json: async () => ({ detail: 'Kolom(men) ontbreken in het bestand: Geplande go-live.' }),
    }))

    await uploadFile()

    expect(await screen.findByRole('alert')).toHaveTextContent('Kolom(men) ontbreken in het bestand: Geplande go-live.')
  })

  it('falls back to the status code when the error has no detail', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 500, json: async () => { throw new Error() } }))

    await uploadFile()

    expect(await screen.findByRole('alert')).toHaveTextContent('Upload mislukt (500).')
  })

  it('says when the server is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')))

    await uploadFile()

    expect(await screen.findByRole('alert')).toHaveTextContent('De server is niet bereikbaar.')
  })
})
