import { useId, useState } from 'react'
import { AiBadge } from '../../components/AiBadge/AiBadge'
import { Banner } from '../../components/Banner/Banner'
import { ChatBubble } from '../../components/ChatBubble/ChatBubble'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { EmptyState } from '../../components/EmptyState/EmptyState'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { SearchField } from '../../components/SearchField/SearchField'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { TypeTag } from '../../components/Tag/Tag'
import { formatDateTime, formatDayMonth } from '../../lib/dates'
import { SAMPLE_CONVERSATIONS, type SampleConversation } from './sampleConversations'
import styles from './ConversationsPage.module.css'

const INPUT: Record<SampleConversation['input'], { icon: string; label: string }> = {
  TEXT: { icon: '/assets/icons/assistant/keyboard.png', label: 'Typed' },
  VOICE: { icon: '/assets/icons/assistant/microphone.png', label: 'Spoken' },
  PHOTO: { icon: '/assets/icons/assistant/photo.png', label: 'Photo' },
}

/**
 * W08 — Conversation history. NOT CONNECTED: the backend can't list conversations
 * yet, so this shows sample data (sampleConversations.ts) under a clear banner.
 */
export function ConversationsPage() {
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState(SAMPLE_CONVERSATIONS[0].id)
  const detailTitleId = useId()

  // Search what was said, in the browser (the sample is small).
  const words = search.trim().toLowerCase()
  const shown = SAMPLE_CONVERSATIONS.filter(
    (conversation) =>
      !words ||
      conversation.title.toLowerCase().includes(words) ||
      conversation.messages.some((message) => message.text.toLowerCase().includes(words)),
  )
  const selected = shown.find((conversation) => conversation.id === selectedId) ?? shown[0]

  const columns: Column<SampleConversation>[] = [
    {
      key: 'conversation',
      header: 'Conversation',
      render: (conversation) => (
        <div className={styles.titleCell}>
          <span className={styles.inputTile}>
            <img src={INPUT[conversation.input].icon} alt={INPUT[conversation.input].label} width={20} height={20} />
          </span>
          <div className={styles.titleText}>
            {/* A real button, so the list also works with the keyboard. */}
            <button
              type="button"
              className={styles.titleButton}
              aria-current={conversation.id === selected?.id ? 'true' : undefined}
              onClick={() => setSelectedId(conversation.id)}
            >
              {conversation.title}
            </button>
            <span className={styles.quote}>“{conversation.messages[0].text}”</span>
          </div>
        </div>
      ),
    },
    { key: 'messages', header: 'Messages', width: '100px', render: (conversation) => conversation.messages.length },
    { key: 'operations', header: 'Operations', width: '160px', render: (conversation) => <OperationCounts conversation={conversation} /> },
    { key: 'last', header: 'Last activity', width: '120px', render: (conversation) => formatDayMonth(conversation.lastActivity) },
  ]

  return (
    <>
      <PageHeader
        title="Conversation history"
        subtitle="Everything you and the assistant said, and what it changed"
        actions={
          <SearchField
            label="Search conversations"
            placeholder="Search words you said…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        }
      />

      <div className={styles.page}>
        <Banner tone="warning" title="Not connected yet — these are sample conversations.">
          The server can’t list past conversations yet (it can only read back the one open in the assistant), so this
          page shows made-up examples. Your real history will appear here once that is added.
        </Banner>

        <div className={styles.layout}>
          <DataTable
            caption="Sample conversations"
            columns={columns}
            rows={shown}
            getRowId={(conversation) => conversation.id}
            getRowLabel={(conversation) => conversation.title}
            onRowClick={(conversation) => setSelectedId(conversation.id)}
            message={
              shown.length === 0 ? (
                <EmptyState title={`No conversations match “${search.trim()}”.`}>
                  <p>Try other words, or clear the search.</p>
                </EmptyState>
              ) : null
            }
          />

          {selected && (
            <section className={styles.detail} aria-labelledby={detailTitleId}>
              <div className={styles.detailHead}>
                <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={34} height={34} />
                <h2 id={detailTitleId} className={styles.detailTitle}>
                  {selected.title}
                </h2>
              </div>
              <p className={styles.meta}>
                {formatDateTime(selected.lastActivity)} · {count(selected.messages.length, 'message')} ·{' '}
                {count(selected.operations.length, 'operation')}
              </p>

              <div className={styles.thread}>
                {selected.messages.map((message, index) => (
                  <ChatBubble key={index} from={message.from} size="sm">
                    {message.text}
                  </ChatBubble>
                ))}
              </div>

              {selected.operations.length > 0 && (
                <div className={styles.operations}>
                  <h3 className={styles.operationsTitle}>Operations from this conversation</h3>
                  <ul className={styles.operationList}>
                    {selected.operations.map((operation) => (
                      <li key={operation.item} className={styles.operation}>
                        <TypeTag type={operation.type} />
                        <span className={styles.operationItem}>{operation.item}</span>
                        {!operation.saved && <StatusPill status="PENDING_CONFIRMATION" />}
                        <span className={operation.estimated ? `${styles.change} ${styles.estimated}` : styles.change}>
                          {operation.estimated && '≈ '}
                          {operation.change}
                        </span>
                        {operation.estimated && <AiBadge compact />}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </section>
          )}
        </div>
      </div>
    </>
  )
}

/** "1 message", "4 messages" */
function count(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`
}

function OperationCounts({ conversation }: { conversation: SampleConversation }) {
  const saved = conversation.operations.filter((operation) => operation.saved).length
  const pending = conversation.operations.length - saved
  if (conversation.operations.length === 0) return <span className={styles.none}>None</span>
  return (
    <span className={styles.counts}>
      {saved > 0 && <span className={`${styles.count} ${styles.saved}`}>{saved} saved</span>}
      {pending > 0 && <span className={`${styles.count} ${styles.pending}`}>{pending} pending</span>}
    </span>
  )
}
