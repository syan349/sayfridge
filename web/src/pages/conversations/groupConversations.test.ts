import { describe, expect, it } from 'vitest'
import type { SavedMessage } from '../../api/agent'
import { groupConversations } from './groupConversations'

const said = (id: string, conversationId: string, role: SavedMessage['role'], content: string, at: string): SavedMessage => ({
  id,
  conversation_id: conversationId,
  role,
  content,
  created_at: at,
})

describe('groupConversations', () => {
  it('groups messages by conversation, newest conversation first, and marks the main chat', () => {
    const groups = groupConversations(
      [
        said('1', 'main', 'USER', 'I bought milk', '2026-10-01T08:00:00Z'),
        said('2', 'side', 'USER', 'What expires soon?', '2026-10-02T08:00:00Z'),
        said('3', 'side', 'ASSISTANT', 'The yogurt, tomorrow.', '2026-10-02T08:00:05Z'),
        said('4', 'main', 'ASSISTANT', 'Added.', '2026-10-01T08:00:05Z'),
      ],
      'main',
    )

    expect(groups.map((group) => group.id)).toEqual(['side', 'main'])
    expect(groups[0]).toMatchObject({ title: 'What expires soon?', isMain: false, lastActivity: '2026-10-02T08:00:05Z' })
    expect(groups[1].isMain).toBe(true)
    expect(groups[1].messages.map((message) => message.id)).toEqual(['1', '4'])
  })

  it('titles a conversation with the first thing the user said, shortened', () => {
    const long = 'I bought two kilograms of rice, a dozen eggs, three litres of milk and some bread today'
    const [group] = groupConversations(
      [
        said('1', 'main', 'ASSISTANT', 'How can I help?', '2026-10-01T08:00:00Z'),
        said('2', 'main', 'USER', `${long}\nand a second line`, '2026-10-01T08:01:00Z'),
      ],
      'main',
    )

    expect(group.title).toBe('I bought two kilograms of rice, a dozen eggs, three litres o…')
  })

  it('returns nothing for no messages', () => {
    expect(groupConversations([], 'main')).toEqual([])
  })
})
