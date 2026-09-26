import { render, screen } from '@testing-library/react'
import { RouterProvider, createMemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { signInAs, testUser } from '../../test/fixtures'
import { renderApp } from '../../test/renderApp'
import { ErrorPage } from './ErrorPage'

describe('Page not found and the error boundary', () => {
  it('shows "Page not found" for an unknown address, with a way back', async () => {
    signInAs(testUser)
    renderApp('/no-such-page')

    expect(await screen.findByRole('heading', { level: 1, name: 'Page not found' })).toBeInTheDocument()
    expect(screen.getByText('/no-such-page')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Go to the dashboard' })).toHaveAttribute('href', '/')
    // Still inside the app: the menu is there.
    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument()
  })

  it('shows the error page instead of a blank screen when a page crashes', async () => {
    // React reports the crash on the console; keep the test output clean.
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
    function BrokenPage(): never {
      throw new Error('Cannot read properties of undefined')
    }
    const router = createMemoryRouter([{ path: '/', element: <BrokenPage />, errorElement: <ErrorPage /> }])
    render(<RouterProvider router={router} />)

    expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on this page.')
    expect(screen.getByRole('button', { name: 'Reload the page' })).toBeInTheDocument()
    expect(screen.getByText('Cannot read properties of undefined')).toBeInTheDocument() // under "Technical details"
    consoleError.mockRestore()
  })
})
