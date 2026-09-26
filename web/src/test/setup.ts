import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterAll, afterEach, beforeAll } from 'vitest'
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

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))

afterEach(() => {
  cleanup() // unmount rendered components
  server.resetHandlers() // drop handlers added by the test
  clearToken() // start every test signed out
})

afterAll(() => server.close())
