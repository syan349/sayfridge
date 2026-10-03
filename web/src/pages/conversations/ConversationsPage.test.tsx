import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { SavedMessage } from '../../api/agent'
import { signInAs, testUser } from '../../test/fixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const MAIN = 'conversation-main'
const SIDE = 'conversation-side'

const said = (id: string, conversationId: string, role: SavedMessage['role'], content: string, minute: number): SavedMessage => ({
  id,
  conversation_id: conversationId,
  role,
  content,
  created_at: `2026-10-02T07:${String(minute).padStart(2, '0')}:00Z`,
})

// Two conversations, mixed together in time order the way the backend returns them.
const newestPage = [
  said('m-3', SIDE, 'USER', 'What can I cook tonight?', 10),
  said('m-4', SIDE, 'ASSISTANT', 'A spinach and yogurt curry would use both.', 11),
  said('m-5', MAIN, 'USER', 'I used two more tomatoes for lunch', 20),
  said('m-6', MAIN, 'ASSISTANT', 'Done. About 9.7 kg of tomatoes left.', 21),
]
const olderPage = [
  said('m-1', MAIN, 'USER', 'I bought 2 L of milk', 1),
  said('m-2', MAIN, 'ASSISTANT', 'Added 2 L of milk to the Fridge.', 2),
]

/** GET /agent/chat: the newest page first; `before=m-3` returns the older page. */
function answerHistory({ complete = true } = {}) {
  const asked: (string | null)[] = []
  server.use(
    http.get('/api/v1/agent/chat', ({ request }) => {
      const before = new URL(request.url).searchParams.get('before')
      asked.push(before)
      return HttpResponse.json({
        conversation_id: MAIN,
        state: { status: 'COMPLETED', items: [] },
        messages: before ? olderPage : newestPage,
        ...(before ? {} : { next_before: 'm-3' }),
        history_complete: complete,
      })
    }),
  )
  return asked
}

beforeEach(() => signInAs(testUser))

describe('ConversationsPage (W08)', () => {
  it('lists the saved conversations, newest first, and shows the newest one', async () => {
    answerHistory()
    renderApp('/conversations')

    const table = await screen.findByRole('table', { name: 'Conversations' })
    await within(table).findByRole('button', { name: 'What can I cook tonight?' }) // loaded
    const rows = within(table).getAllByRole('row')
    expect(rows).toHaveLength(3) // header + 2 conversations
    expect(rows[1]).toHaveTextContent('I used two more tomatoes for lunch')
    expect(rows[1]).toHaveTextContent('Main chat')
    expect(rows[2]).toHaveTextContent('What can I cook tonight?')

    // The newest conversation is open on the right, with what both sides said.
    const detail = screen.getByRole('region', { name: 'I used two more tomatoes for lunch' })
    expect(within(detail).getByText('Done. About 9.7 kg of tomatoes left.')).toBeInTheDocument()
    expect(within(detail).getByRole('link', { name: 'Continue in the assistant' })).toHaveAttribute('href', '/assistant')
    expect(screen.queryByText(/sample conversations/i)).not.toBeInTheDocument()
  })

  it('opens another conversation', async () => {
    answerHistory()
    const user = userEvent.setup()
    renderApp('/conversations')

    await user.click(await screen.findByRole('button', { name: 'What can I cook tonight?' }))

    const detail = screen.getByRole('region', { name: 'What can I cook tonight?' })
    expect(within(detail).getByText('A spinach and yogurt curry would use both.')).toBeInTheDocument()
    expect(within(detail).queryByText('Done. About 9.7 kg of tomatoes left.')).not.toBeInTheDocument()
  })

  it('loads older messages with the cursor the backend gave', async () => {
    const asked = answerHistory()
    const user = userEvent.setup()
    renderApp('/conversations')

    await user.click(await screen.findByRole('button', { name: 'Load older messages' }))

    // The older page belongs to the main chat: its count grows and its first message is now the title.
    expect(await screen.findByRole('button', { name: 'I bought 2 L of milk' })).toBeInTheDocument()
    expect(asked).toEqual([null, 'm-3'])
    expect(screen.queryByRole('button', { name: 'Load older messages' })).not.toBeInTheDocument() // no more pages
  })

  it('searches what was said', async () => {
    answerHistory()
    const user = userEvent.setup()
    renderApp('/conversations')

    const search = await screen.findByLabelText('Search conversations')
    await screen.findByRole('button', { name: 'What can I cook tonight?' })
    await user.type(search, 'curry')
    expect(screen.getAllByRole('row')).toHaveLength(2) // header + the one that mentions curry
    expect(screen.getByRole('button', { name: 'What can I cook tonight?' })).toBeInTheDocument()

    await user.clear(search)
    await user.type(search, 'pizza')
    expect(screen.getByText('No conversations match “pizza”.')).toBeInTheDocument()
  })

  it('says so when some older history may be missing', async () => {
    answerHistory({ complete: false })
    renderApp('/conversations')

    expect(await screen.findByText('Some older messages may be missing.')).toBeInTheDocument()
  })

  it('shows an empty state before anything was said', async () => {
    renderApp('/conversations') // the default test backend: a main chat with no messages

    expect(await screen.findByText('No conversations yet.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ask the assistant' })).toHaveAttribute('href', '/assistant')
  })

  it('shows an error with Try again when history can’t be loaded', async () => {
    let calls = 0
    server.use(
      http.get('/api/v1/agent/chat', () => {
        calls += 1
        return calls === 1
          ? HttpResponse.json({ detail: { code: 'AGENT_UNAVAILABLE' } }, { status: 503 })
          : HttpResponse.json({ conversation_id: MAIN, state: { status: 'COMPLETED', items: [] }, messages: newestPage, history_complete: true })
      }),
    )
    const user = userEvent.setup()
    renderApp('/conversations')

    expect(await screen.findByRole('alert')).toHaveTextContent('We couldn’t load your conversations.')
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByRole('button', { name: 'What can I cook tonight?' })).toBeInTheDocument()
  })
})
