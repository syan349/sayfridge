import '@testing-library/jest-dom/vitest'
import { cleanup, configure } from '@testing-library/react'
import { afterAll, afterEach, beforeAll, vi } from 'vitest'
import { clearToken } from '../api/tokenStore'
import { server } from './server'

// jsdom (the fake browser used by tests) has <dialog> but not its showModal()
// and close() methods. Real browsers have them; tests only need open/closed.
HTMLDialogElement.prototype.showModal ??= function (this: HTMLDialogElement) {
  this.setAttribute('open', '')
}
HTMLDialogElement.prototype.close ??= function (this: HTMLDialogElement) {
  this.removeAttribute('open')
  this.dispatchEvent(new Event('close'))
}

// findBy…/waitFor give up after 1 second by default. A whole page (router, auth,
// several requests) can take longer when every test file runs at once on a busy
// machine or CI runner, which made a few tests fail at random. 3 seconds is still quick.
// For the same reason a whole test (e.g. filling in two batch rows) may take 15 s, not 5.
configure({ asyncUtilTimeout: 3000 })
vi.setConfig({ testTimeout: 15_000 })

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))

afterEach(() => {
  cleanup() // unmount rendered components
  server.resetHandlers() // drop handlers added by the test
  clearToken() // start every test signed out
})

afterAll(() => server.close())
