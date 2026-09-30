import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { AgentEvent, AgentItem } from '../../api/agent'
import { todayLocal } from '../../lib/dates'
import { signInAs, testUser } from '../../test/fixtures'
import { page, tomatoes } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const STORAGE_KEY = `sayfridge.assistant.${testUser.id}`

/** What the backend streams back: each event as "event: …" + "data: {json}" + a blank line. */
function sse(...events: AgentEvent[]) {
  const body = events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join('')
  return new HttpResponse(body, { headers: { 'Content-Type': 'text/event-stream' } })
}

const start: AgentEvent = { type: 'start', conversation_id: 'conversation-1', request_id: 'r' }

const tomatoesBefore = { ...tomatoes, estimated_current_amount: null, display_amount: '10.000', is_estimated: false }

/** "Two more tomatoes" → about 0.3 kg: an estimate, so it needs the user's confirmation. */
const proposal: AgentItem = {
  item_id: 'item-1',
  item_key: 'tomatoes',
  proposal_id: 'proposal-1',
  status: 'NEEDS_CONFIRMATION',
  original_text: 'two more tomatoes',
  preview: {
    draft: { action: 'CONSUME', item_query: 'tomatoes', quantity_value: '2', quantity_unit: 'each' },
    before: tomatoesBefore,
    after: { amount: '9.700', unit: 'kg', is_estimated: true },
    requires_confirmation: true,
  },
}

/** The stream of a turn that stops to ask for confirmation. */
const askToConfirm = () =>
  sse(
    start,
    { type: 'operation_preview', data: proposal },
    { type: 'action_required', data: { interrupt_id: 'interrupt-1', items: [proposal] } },
    { type: 'done', status: 'WAITING_INPUT', data: { status: 'WAITING_INPUT', items: [proposal], interrupt_id: 'interrupt-1' } },
  )

beforeEach(() => {
  sessionStorage.clear()
  signInAs(testUser)
})

afterEach(() => sessionStorage.clear())

describe('AssistantPage (W07)', () => {
  it('renders hostile model text as text, never executable HTML', async () => {
    const payload = '<img src=x onerror="window.pwned=true"><script>alert(1)</script>'
    server.use(http.post('/api/v1/agent/chat', () => sse(
      start,
      { type: 'text_delta', delta: payload },
      { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } },
    )))
    const user = userEvent.setup()
    renderApp('/assistant')
    await user.type(await screen.findByLabelText('Message the assistant'), 'hello')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    expect(await screen.findByText(payload)).toBeInTheDocument()
    expect(document.body.querySelector('script, img[src="x"], [onerror]')).toBeNull()
  })

  it('streams the answer into the chat, and sends today’s local date and a request id', async () => {
    let body: Record<string, unknown> = {}
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>
        return sse(
          start,
          { type: 'text_delta', delta: 'Spinach and yogurt ' },
          { type: 'text_delta', delta: 'expire tomorrow.' },
          { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } },
        )
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await screen.findByLabelText('Message the assistant'), 'What expires soon?')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    // The pieces of text are joined into one reply bubble.
    expect(await screen.findByText('Spinach and yogurt expire tomorrow.')).toBeInTheDocument()
    expect(screen.getByText('What expires soon?')).toBeInTheDocument()
    expect(body).toEqual({ message: 'What expires soon?', as_of: todayLocal(), request_id: expect.stringMatching(UUID) })
    expect(sessionStorage.getItem(STORAGE_KEY)).toBe('conversation-1') // kept for a reload
  })

  it('shows a proposal, and Confirm sends it back with POST /agent/resume', async () => {
    let resumeBody: unknown
    let inventoryRequests = 0
    server.use(
      http.get('/api/v1/inventory-items', () => {
        inventoryRequests += 1
        return HttpResponse.json(page([]))
      }),
      http.post('/api/v1/agent/chat', askToConfirm),
      http.post('/api/v1/agent/resume', async ({ request }) => {
        resumeBody = await request.json()
        const saved: AgentItem = { ...proposal, status: 'SUCCEEDED', result: { inventory: tomatoes } }
        return sse(
          start,
          { type: 'operation_result', data: saved },
          { type: 'text_delta', delta: 'Done — about 9.7 kg of tomatoes left.' },
          { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [saved] } },
        )
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await screen.findByLabelText('Message the assistant'), 'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    const card = await screen.findByRole('region', { name: 'One proposed change' })
    expect(within(card).getByText('Tomatoes')).toBeInTheDocument()
    expect(within(card).getByText('Vegetables · Fridge · consume 2 each')).toBeInTheDocument()
    expect(within(card).getByText(/9\.7 kg/)).toBeInTheDocument()
    expect(within(card).getByAltText('AI estimate')).toBeInTheDocument()
    // Nothing else can be sent until the proposal is answered.
    expect(screen.getByLabelText('Message the assistant')).toBeDisabled()

    const requestsBefore = inventoryRequests
    await user.click(within(card).getByRole('button', { name: 'Confirm' }))

    expect(await screen.findByText('Done — about 9.7 kg of tomatoes left.')).toBeInTheDocument()
    expect(resumeBody).toEqual({
      conversation_id: 'conversation-1',
      interrupt_id: 'interrupt-1',
      request_id: expect.stringMatching(UUID),
      responses: [{ item_id: 'item-1', proposal_id: 'proposal-1', decision: 'confirm' }],
    })
    expect(screen.queryByRole('region', { name: 'One proposed change' })).not.toBeInTheDocument()
    const rail = screen.getByRole('complementary', { name: 'This conversation' })
    expect(within(rail).getByText('Saved')).toBeInTheDocument()
    // The stock changed, so the inventory numbers (e.g. in the sidebar) are fetched again.
    await waitFor(() => expect(inventoryRequests).toBeGreaterThan(requestsBefore))
  })

  it('Edit sends what should change, in the user’s words', async () => {
    let resumeBody: { responses?: unknown } = {}
    server.use(
      http.post('/api/v1/agent/chat', askToConfirm),
      http.post('/api/v1/agent/resume', async ({ request }) => {
        resumeBody = (await request.json()) as { responses?: unknown }
        return sse(start, { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } })
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await screen.findByLabelText('Message the assistant'), 'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    const card = await screen.findByRole('region', { name: 'One proposed change' })
    await user.click(within(card).getByRole('button', { name: 'Edit' }))
    await user.type(within(card).getByLabelText('What should change?'), 'It was three tomatoes')
    await user.click(within(card).getByRole('button', { name: 'Send' }))

    await waitFor(() =>
      expect(resumeBody.responses).toEqual([
        { item_id: 'item-1', proposal_id: 'proposal-1', decision: 'edit', message: 'It was three tomatoes' },
      ]),
    )
    expect(screen.getByText('It was three tomatoes')).toBeInTheDocument() // shown as the user's message
  })

  it('brings the conversation back after a reload, with the proposal still waiting', async () => {
    sessionStorage.setItem(STORAGE_KEY, 'conversation-1')
    server.use(
      http.get('/api/v1/agent/conversations/:id/state', ({ params }) =>
        params.id === 'conversation-1'
          ? HttpResponse.json({ status: 'WAITING_INPUT', items: [proposal], interrupt_id: 'interrupt-1' })
          : HttpResponse.json({ detail: { code: 'NOT_FOUND' } }, { status: 404 }),
      ),
    )
    renderApp('/assistant')

    expect(await screen.findByRole('region', { name: 'One proposed change' })).toBeInTheDocument()
    expect(screen.getByText(/The server may retain conversation history/)).toBeInTheDocument()
  })

  it('offers Try again when the answer breaks off, and retries with the same request id', async () => {
    const requestIds: unknown[] = []
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        const body = (await request.json()) as { request_id: string }
        requestIds.push(body.request_id)
        return requestIds.length === 1
          ? sse(start, { type: 'error', code: 'AGENT_EXECUTION_FAILED', message: 'Execution interrupted' })
          : sse(
              start,
              { type: 'text_delta', delta: 'You have 2 L of milk.' },
              { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } },
            )
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await screen.findByLabelText('Message the assistant'), 'How much milk is left?')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('The assistant stopped before it finished.')
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByText('You have 2 L of milk.')).toBeInTheDocument()
    expect(requestIds).toHaveLength(2)
    expect(requestIds[1]).toBe(requestIds[0]) // the same request, so the backend won't do it twice
  })

  it('says so when the assistant is unavailable', async () => {
    server.use(
      http.post('/api/v1/agent/chat', () =>
        HttpResponse.json({ detail: { code: 'AGENT_UNAVAILABLE', message: 'Agent storage is unavailable' } }, { status: 503 }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.click(await screen.findByRole('button', { name: 'I used 2 eggs' })) // a suggestion sends straight away

    expect(await screen.findByRole('alert')).toHaveTextContent('The assistant isn’t available right now.')
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument()
  })
})
