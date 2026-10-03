import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { AgentEvent, AgentItem, ChatHistory, SavedMessage } from '../../api/agent'
import { todayLocal } from '../../lib/dates'
import { signInAs, testUser } from '../../test/fixtures'
import { page, tomatoes } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

// Shrinking a photo needs a real browser (a canvas). Here it is replaced by a stand-in
// that returns a tiny fixed photo, so these tests check what is SENT, not the pixels.
vi.mock('../../lib/photos', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/photos')>()),
  preparePhoto: async (file: File) => ({
    image: { image_id: `photo-${file.name}`, mime_type: 'image/jpeg', data_base64: 'QUJD' },
    previewUrl: 'data:image/jpeg;base64,QUJD',
    name: file.name,
  }),
}))

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

/** The message box, once the saved chat has loaded (it is disabled until then). */
async function messageBox() {
  const box = await screen.findByLabelText('Message the assistant')
  await waitFor(() => expect(box).toBeEnabled())
  return box
}

/** GET /agent/chat: the user's main chat, with these saved messages and this state. */
function answerHistory(history: Partial<ChatHistory>) {
  server.use(
    http.get('/api/v1/agent/chat', () =>
      HttpResponse.json({
        conversation_id: 'conversation-1',
        state: { status: 'COMPLETED', items: [] },
        messages: [],
        history_complete: true,
        ...history,
      }),
    ),
  )
}

const said = (id: string, role: SavedMessage['role'], content: string, conversationId = 'conversation-1'): SavedMessage => ({
  id,
  conversation_id: conversationId,
  role,
  content,
  created_at: '2026-10-02T07:28:00Z',
})

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
    await user.type(await messageBox(),'hello')
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

    await user.type(await messageBox(),'What expires soon?')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    // The pieces of text are joined into one reply bubble.
    expect(await screen.findByText('Spinach and yogurt expire tomorrow.')).toBeInTheDocument()
    expect(screen.getByText('What expires soon?')).toBeInTheDocument()
    // It continues the main chat that GET /agent/chat opened.
    expect(body).toEqual({
      message: 'What expires soon?',
      as_of: todayLocal(),
      request_id: expect.stringMatching(UUID),
      conversation_id: 'conversation-1',
    })
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull() // the backend remembers the main chat; nothing to store
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

    await user.type(await messageBox(),'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    const card = await screen.findByRole('region', { name: 'One proposed change' })
    expect(within(card).getByText('Tomatoes')).toBeInTheDocument()
    expect(within(card).getByText('Vegetables · Fridge · consume 2 each')).toBeInTheDocument()
    expect(within(card).getByText(/9\.7 kg/)).toBeInTheDocument()
    expect(within(card).getByAltText('AI estimate')).toBeInTheDocument()
    // The message box stays open: a reply there goes to the waiting proposal.
    expect(screen.getByLabelText('Message the assistant')).toBeEnabled()

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

    await user.type(await messageBox(),'I used two more tomatoes')
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

  it('opens the saved main chat: earlier messages, and a proposal that is still waiting', async () => {
    answerHistory({
      state: { status: 'WAITING_INPUT', items: [proposal], interrupt_id: 'interrupt-1' },
      messages: [
        said('m-1', 'USER', 'I used two more tomatoes'),
        said('m-2', 'ASSISTANT', 'Two tomatoes is about 0.3 kg. Shall I record that?'),
        said('m-3', 'USER', 'Something said in another conversation', 'conversation-2'),
      ],
      next_before: 'm-1',
    })
    renderApp('/assistant')

    expect(await screen.findByRole('region', { name: 'One proposed change' })).toBeInTheDocument()
    expect(screen.getByText('I used two more tomatoes')).toBeInTheDocument()
    expect(screen.getByText('Two tomatoes is about 0.3 kg. Shall I record that?')).toBeInTheDocument()
    // History covers every conversation; only the one being continued is shown here.
    expect(screen.queryByText('Something said in another conversation')).not.toBeInTheDocument()
    // Older pages exist: they are on the history page.
    expect(screen.getByRole('link', { name: 'Conversation history' })).toHaveAttribute('href', '/conversations')
  })

  it('sends photos with a message, shrunk and encoded, and shows them in the chat', async () => {
    let body: { message?: string; images?: unknown } = {}
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        body = (await request.json()) as typeof body
        return sse(start, { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } })
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')
    await messageBox()

    await user.upload(screen.getByLabelText('Attach photos'), new File(['pixels'], 'receipt.jpg', { type: 'image/jpeg' }))
    expect(await screen.findByAltText('Photo 1: receipt.jpg')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Send' })) // a photo alone can be sent

    await waitFor(() =>
      expect(body.images).toEqual([{ image_id: 'photo-receipt.jpg', mime_type: 'image/jpeg', data_base64: 'QUJD' }]),
    )
    expect(body.message).toBe('')
    expect(screen.getByAltText('Photo you sent: receipt.jpg')).toBeInTheDocument()
    expect(screen.queryByAltText('Photo 1: receipt.jpg')).not.toBeInTheDocument() // the box is empty again
  })

  it('refuses a file that isn’t a JPEG, PNG or WebP photo, and more than four photos', async () => {
    // applyAccept: false = as if the file was dragged in, past the file dialog's filter.
    const user = userEvent.setup({ applyAccept: false })
    renderApp('/assistant')
    await messageBox()
    const attach = screen.getByLabelText('Attach photos')

    await user.upload(attach, new File(['x'], 'IMG_0001.heic', { type: 'image/heic' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('“IMG_0001.heic” isn’t a JPEG, PNG or WebP photo.')

    const five = [1, 2, 3, 4, 5].map((n) => new File(['x'], `shelf-${n}.png`, { type: 'image/png' }))
    await user.upload(attach, five)
    expect(await screen.findByRole('alert')).toHaveTextContent('You can send at most 4 photos at a time.')
    expect(screen.queryByAltText(/^Photo 1/)).not.toBeInTheDocument()
  })

  it('New conversation starts a separate one, and Back to main chat returns to the saved chat', async () => {
    let body: { conversation_id?: string } = {}
    answerHistory({ messages: [said('m-1', 'USER', 'What expires soon?'), said('m-2', 'ASSISTANT', 'Milk, tomorrow.')] })
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        body = (await request.json()) as typeof body
        return sse(
          { type: 'start', conversation_id: body.conversation_id!, request_id: 'r' },
          { type: 'text_delta', delta: 'Noted.' },
          { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } },
        )
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')
    expect(await screen.findByText('Milk, tomorrow.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'New conversation' }))
    expect(screen.queryByText('Milk, tomorrow.')).not.toBeInTheDocument()
    await user.type(await messageBox(), 'I bought rice')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    expect(await screen.findByText('Noted.')).toBeInTheDocument()

    // A new id made by the browser, kept for this tab so a reload stays in this conversation.
    expect(body.conversation_id).toMatch(UUID)
    expect(body.conversation_id).not.toBe('conversation-1')
    expect(sessionStorage.getItem(STORAGE_KEY)).toBe(body.conversation_id)

    await user.click(screen.getByRole('button', { name: 'Back to main chat' }))
    expect(await screen.findByText('Milk, tomorrow.')).toBeInTheDocument()
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull()
    expect(screen.queryByRole('button', { name: 'Back to main chat' })).not.toBeInTheDocument()
  })

  it('still lets you chat when the saved chat can’t be loaded', async () => {
    server.use(
      http.get('/api/v1/agent/chat', () =>
        HttpResponse.json({ detail: { code: 'AGENT_UNAVAILABLE' } }, { status: 503 }),
      ),
    )
    renderApp('/assistant')

    expect(await screen.findByRole('alert')).toHaveTextContent('We couldn’t load your saved conversation.')
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument()
    expect(await messageBox()).toBeEnabled()
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

    await user.type(await messageBox(),'How much milk is left?')
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

  it('asks the backend’s own question, not its internal message', async () => {
    const question: AgentItem = {
      item_id: 'item-2',
      item_key: 'milk',
      proposal_id: 'proposal-2',
      status: 'NEEDS_INPUT',
      original_text: 'I bought milk',
      preview: null,
      error: { code: 'SPACE_REQUIRED', message: 'Select a storage space' },
      display: { item_name: 'Milk', question: 'Where would you like to store the milk?' },
    }
    server.use(
      http.post('/api/v1/agent/chat', () =>
        sse(
          start,
          { type: 'action_required', data: { interrupt_id: 'interrupt-2', items: [question] } },
          { type: 'done', status: 'WAITING_INPUT', data: { status: 'WAITING_INPUT', items: [question], interrupt_id: 'interrupt-2' } },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await messageBox(),'I bought milk')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    const card = await screen.findByRole('region', { name: 'One proposed change' })
    expect(within(card).getByText('Milk')).toBeInTheDocument()
    expect(within(card).getByText('Where would you like to store the milk?')).toBeInTheDocument()
    expect(screen.queryByText('Select a storage space')).not.toBeInTheDocument()
  })

  it('a reply in the message box answers the waiting proposal', async () => {
    let chatBodies: Record<string, unknown>[] = []
    server.use(
      http.post('/api/v1/agent/chat', async ({ request }) => {
        chatBodies = [...chatBodies, (await request.json()) as Record<string, unknown>]
        return chatBodies.length === 1
          ? askToConfirm()
          : sse(start, { type: 'done', status: 'COMPLETED', data: { status: 'COMPLETED', items: [] } })
      }),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await messageBox(),'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    await screen.findByRole('region', { name: 'One proposed change' })
    await user.type(screen.getByLabelText('Message the assistant'), 'It was three tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    // Sent to the same conversation; the backend gives it to the waiting item.
    await waitFor(() => expect(chatBodies).toHaveLength(2))
    expect(chatBodies[1]).toMatchObject({ message: 'It was three tomatoes', conversation_id: 'conversation-1' })
  })

  it('offers only Confirm for a change that may already have been saved', async () => {
    const uncertain: AgentItem = {
      ...proposal,
      error: { code: 'EXECUTION_UNCERTAIN', message: 'Service unavailable' },
    }
    server.use(
      http.post('/api/v1/agent/chat', () =>
        sse(
          start,
          { type: 'action_required', data: { interrupt_id: 'interrupt-1', items: [uncertain] } },
          { type: 'done', status: 'WAITING_INPUT', data: { status: 'WAITING_INPUT', items: [uncertain], interrupt_id: 'interrupt-1' } },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await messageBox(),'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))

    const card = await screen.findByRole('region', { name: 'One proposed change' })
    expect(within(card).getByText(/It isn’t certain this was saved/)).toBeInTheDocument()
    expect(within(card).getByRole('button', { name: 'Confirm' })).toBeInTheDocument()
    // The backend refuses edit/cancel for such an item (409), so they aren't offered.
    expect(within(card).queryByRole('button', { name: 'Edit' })).not.toBeInTheDocument()
    expect(within(card).queryByRole('button', { name: 'Cancel' })).not.toBeInTheDocument()
  })

  it('keeps “that proposal changed” on screen while it loads the latest version', async () => {
    const newer: AgentItem = {
      ...proposal,
      proposal_id: 'proposal-1b',
      preview: { ...proposal.preview!, draft: { ...proposal.preview!.draft, quantity_value: '3' } },
    }
    server.use(
      http.post('/api/v1/agent/chat', askToConfirm),
      http.post('/api/v1/agent/resume', () =>
        HttpResponse.json({ detail: { code: 'STALE_PROPOSAL' } }, { status: 409 }),
      ),
      http.get('/api/v1/agent/conversations/:id/state', () =>
        HttpResponse.json({ status: 'WAITING_INPUT', items: [newer], interrupt_id: 'interrupt-1b' }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/assistant')

    await user.type(await messageBox(),'I used two more tomatoes')
    await user.click(screen.getByRole('button', { name: 'Send' }))
    const card = await screen.findByRole('region', { name: 'One proposed change' })
    await user.click(within(card).getByRole('button', { name: 'Confirm' }))

    // The card now shows the latest version, and the message explaining why is still there.
    expect(await screen.findByText('Vegetables · Fridge · consume 3 each')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('That proposal changed in the meantime.')
    // The messages already on screen are kept.
    expect(screen.getByText('I used two more tomatoes')).toBeInTheDocument()
  })
})
