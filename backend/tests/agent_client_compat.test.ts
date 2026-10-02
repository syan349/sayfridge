import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { createElement, type ReactNode } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, expect, it } from 'vitest'
import { http, HttpResponse } from 'msw'
import { readEventStream, type AgentEvent } from '../../web/src/api/agent'
import { setToken } from '../../web/src/api/tokenStore'
import { useAssistant } from '../../web/src/pages/assistant/useAssistant'
import { server } from '../../web/src/test/server'

interface Trace {
  path: string
  method: string
  request: Record<string, unknown> | null
  status: number
  content_type: string
  body: string
}
const path = process.env.AGENT_CLIENT_CAPTURE_FILE ?? fileURLToPath(new URL('../.venv/chat_client_traces.jsonl', import.meta.url))
const traces: Trace[] = readFileSync(path, 'utf8').trim().split('\n').map((line) => JSON.parse(line))
const streams = traces.filter((r) => r.status === 200 && r.content_type.includes('event-stream'))
const events = (r: Trace): AgentEvent[] => r.body.split('\n').filter((s) => s.startsWith('data: ')).map((s) => JSON.parse(s.slice(6)))
const completed = streams.find((r) => r.path.endsWith('/chat') && events(r).at(-1)?.type === 'done' && events(r).some((e) => e.type === 'text_delta'))!

beforeEach(() => {
  sessionStorage.clear()
  setToken('isolated-client-test-token', 900)
})

it('unchanged Web parser consumes actual backend responses across UTF-8 chunks and heartbeat comments', async () => {
  expect(streams.length).toBeGreaterThan(10)
  for (const row of streams) {
    const bytes = new TextEncoder().encode(': keep-alive\n\n' + row.body)
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        for (let n = 0; n < bytes.length; n += 17) controller.enqueue(bytes.slice(n, n + 17))
        controller.close()
      },
    })
    const actual: AgentEvent[] = []
    await readEventStream(new Response(body), (event) => actual.push(event))
    expect(actual).toEqual(events(row))
  }
})

it('unchanged Web hook keeps the start ID and resends the whole request after a truncated real response', async () => {
  const sent: Record<string, unknown>[] = []
  server.use(http.post('/api/v1/agent/chat', async ({ request }) => {
    sent.push(await request.json() as Record<string, unknown>)
    const body = sent.length === 1 ? completed.body.slice(0, completed.body.indexOf('event: done')) : completed.body
    return new HttpResponse(body, { headers: { 'Content-Type': completed.content_type } })
  }))
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client }, children)
  const { result } = renderHook(() => useAssistant('compat-web'), { wrapper })
  act(() => result.current.sendMessage('Existing Web first message'))
  await waitFor(() => expect(result.current.state.error?.canRetry).toBe(true))
  const start = events(completed)[0]
  expect(start.type).toBe('start')
  if (start.type !== 'start') throw new Error('backend start missing')
  expect(result.current.state.conversationId).toBe(start.conversation_id)
  expect(sessionStorage.getItem('sayfridge.assistant.compat-web')).toBe(start.conversation_id)
  expect(sent[0].conversation_id).toBeUndefined()
  act(() => result.current.retry())
  await waitFor(() => expect(sent.length).toBe(2))
  await waitFor(() => expect(result.current.state.busy).toBe(false))
  expect(sent[1]).toEqual(sent[0])
  expect(result.current.state.error).toBeNull()
  expect(result.current.state.messages.some((m) => m.from === 'assistant' && m.text.length > 0)).toBe(true)
})

it('unchanged Web hook restores an actual pending state and confirms its original proposal', async () => {
  const waiting = traces.find((r) => r.method === 'GET' && r.path.endsWith('/state') && r.status === 200 && JSON.parse(r.body).status === 'WAITING_INPUT')!
  const state = JSON.parse(waiting.body)
  const cid = waiting.path.split('/')[5]
  const resume = streams.find((r) => r.path.endsWith('/resume') && r.request?.conversation_id === cid
    && (r.request.responses as { decision: string }[]).some((a) => a.decision === 'confirm') && events(r).at(-1)?.type === 'done')!
  expect(resume).toBeDefined()
  sessionStorage.setItem('sayfridge.assistant.compat-restore', cid)
  server.use(http.get(`/api/v1/agent/conversations/${cid}/state`, () => HttpResponse.json(state)),
    http.post('/api/v1/agent/resume', async ({ request }) => {
      const body = await request.json() as Record<string, unknown>
      expect(body.conversation_id).toBe(cid)
      expect(body.interrupt_id).toBe(state.interrupt_id)
      return new HttpResponse(resume.body, { headers: { 'Content-Type': resume.content_type } })
    }))
  const client = new QueryClient()
  const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client }, children)
  const { result } = renderHook(() => useAssistant('compat-restore'), { wrapper })
  await waitFor(() => expect(result.current.state.interruptId).toBe(state.interrupt_id))
  const pending = result.current.state.items.find((i) => i.status === 'NEEDS_CONFIRMATION')!
  expect(pending).toBeDefined()
  act(() => result.current.answer([{ item_id: pending.item_id, proposal_id: pending.proposal_id, decision: 'confirm' }]))
  await waitFor(() => expect(result.current.state.items.some((i) => i.status === 'SUCCEEDED')).toBe(true))
  expect(result.current.state.conversationId).toBe(cid)
})
