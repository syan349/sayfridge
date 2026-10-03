import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import type { ReactNode } from 'react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { AgentEvent } from '../../api/agent'
import { setToken } from '../../api/tokenStore'
import { server } from '../../test/server'
import { useAssistant } from './useAssistant'

const STORAGE_KEY = 'sayfridge.assistant.user-1'

function sse(...events: AgentEvent[]) {
  const body = events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('')
  return new HttpResponse(body, { headers: { 'Content-Type': 'text/event-stream' } })
}

function renderAssistant() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>
  return renderHook(() => useAssistant('user-1'), { wrapper })
}

beforeEach(() => {
  sessionStorage.clear()
  setToken('test-token', 900)
})

afterEach(() => sessionStorage.clear())

describe('useAssistant', () => {
  // The page disables the message box while the saved chat loads, so this can only
  // happen to code that uses the hook directly. It still must not lose the message.
  it('keeps a message sent before the saved chat arrived, as its own conversation', async () => {
    const sent: Record<string, unknown>[] = []
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        sent.push((await request.json()) as Record<string, unknown>)
        return sse(
          { type: 'start', conversation_id: 'started-early', request_id: 'r' },
          { type: 'text_delta', delta: 'Hello!' },
          { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } },
        )
      }),
    )
    const { result } = renderAssistant()

    act(() => result.current.sendMessage('Hi')) // the saved chat (GET /agent/chat) hasn't answered yet
    await waitFor(() => expect(result.current.state.opening).toBe(false))
    await waitFor(() => expect(result.current.state.busy).toBe(false))

    expect(sent[0].conversation_id).toBeUndefined() // no id yet: the backend starts a conversation
    expect(result.current.state.messages.map((message) => message.text)).toEqual(['Hi', 'Hello!'])
    expect(result.current.state.conversationId).toBe('started-early')
    expect(result.current.state.side).toBe(true) // it isn't the main chat ("conversation-1")
    expect(sessionStorage.getItem(STORAGE_KEY)).toBe('started-early') // a reload stays in it
  })

  it('doesn’t store the main chat’s id: the backend already knows it', async () => {
    const { result } = renderAssistant()

    await waitFor(() => expect(result.current.state.conversationId).toBe('conversation-1'))

    expect(result.current.state.side).toBe(false)
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull()
  })
})
