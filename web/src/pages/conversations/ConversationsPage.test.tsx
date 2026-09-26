import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it } from 'vitest'
import { signInAs, testUser } from '../../test/fixtures'
import { renderApp } from '../../test/renderApp'

beforeEach(() => signInAs(testUser))

describe('ConversationsPage (W08, sample data)', () => {
  it('says clearly that it isn’t connected, and shows the sample conversations', async () => {
    renderApp('/conversations')

    expect(await screen.findByText('Not connected yet — these are sample conversations.')).toBeInTheDocument()
    const table = screen.getByRole('table', { name: 'Sample conversations' })
    expect(within(table).getAllByRole('row')).toHaveLength(6) // header + 5 conversations
    // The first one is open on the right.
    expect(screen.getByRole('heading', { level: 2, name: 'Tomatoes for lunch' })).toBeInTheDocument()
  })

  it('opens another conversation with its messages and operations', async () => {
    const user = userEvent.setup()
    renderApp('/conversations')

    await user.click(await screen.findByRole('button', { name: 'Weekly shop, typed in' }))

    const detail = screen.getByRole('region', { name: 'Weekly shop, typed in' })
    expect(within(detail).getByText('add 2L milk, a dozen eggs and 1 kg of rice')).toBeInTheDocument()
    expect(within(detail).getByText('Eggs')).toBeInTheDocument()
    expect(within(detail).getByText('+12 each')).toBeInTheDocument()
  })

  it('searches what was said', async () => {
    const user = userEvent.setup()
    renderApp('/conversations')

    const search = await screen.findByLabelText('Search conversations')
    await user.type(search, 'curry')
    expect(screen.getAllByRole('row')).toHaveLength(2) // header + "What can I cook tonight?"
    expect(screen.getByRole('button', { name: 'What can I cook tonight?' })).toBeInTheDocument()

    await user.clear(search)
    await user.type(search, 'pizza')
    expect(screen.getByText('No conversations match “pizza”.')).toBeInTheDocument()
  })
})
