import type { SavedMessage } from '../../api/agent'

/** One conversation, built from the saved messages that carry its id. */
export interface ConversationSummary {
  id: string
  /** The first thing the user said in it (shortened), so it can be recognised in the list. */
  title: string
  /** Oldest first. */
  messages: SavedMessage[]
  /** When the newest message was sent (ISO timestamp). */
  lastActivity: string
  /** The chat the assistant page continues by default. */
  isMain: boolean
}

const TITLE_LENGTH = 60

function titleOf(messages: SavedMessage[]): string {
  const firstSaid = messages.find((message) => message.role === 'USER') ?? messages[0]
  const firstLine = firstSaid.content.split('\n')[0].trim()
  if (!firstLine) return 'Conversation'
  return firstLine.length > TITLE_LENGTH ? `${firstLine.slice(0, TITLE_LENGTH).trimEnd()}…` : firstLine
}

/**
 * The backend returns ONE list of saved messages across all of the user's conversations;
 * each message says which conversation it belongs to. This groups them, newest
 * conversation first. `messages` must be in time order (oldest first).
 */
export function groupConversations(messages: SavedMessage[], mainId: string): ConversationSummary[] {
  const byId = new Map<string, SavedMessage[]>()
  for (const message of messages) {
    const group = byId.get(message.conversation_id)
    if (group) group.push(message)
    else byId.set(message.conversation_id, [message])
  }
  return [...byId.entries()]
    .map(([id, group]) => ({
      id,
      title: titleOf(group),
      messages: group,
      lastActivity: group[group.length - 1].created_at,
      isMain: id === mainId,
    }))
    .sort((a, b) => b.lastActivity.localeCompare(a.lastActivity))
}
