import { useInfiniteQuery } from '@tanstack/react-query'
import { useId, useState, type ReactNode } from 'react'
import { getChatHistory } from '../../api/agent'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { ChatBubble } from '../../components/ChatBubble/ChatBubble'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { EmptyState } from '../../components/EmptyState/EmptyState'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { SearchField } from '../../components/SearchField/SearchField'
import { formatDateTime, formatRelative } from '../../lib/dates'
import { groupConversations, type ConversationSummary } from './groupConversations'
import styles from './ConversationsPage.module.css'

/** "1 message", "4 messages" */
function count(n: number, word: string): string {
  return `${n} ${word}${n === 1 ? '' : 's'}`
}

/**
 * W08 — Conversation history: what you and the assistant said, saved by the backend
 * (GET /agent/chat). Messages arrive newest page first; "Load older messages" pages back.
 */
export function ConversationsPage() {
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const detailTitleId = useId()

  // Each page is up to 100 saved messages. The same key is refreshed by the assistant
  // page after every answer, so new messages show up here.
  const history = useInfiniteQuery({
    queryKey: ['agent', 'history'],
    queryFn: ({ pageParam, signal }) => getChatHistory({ before: pageParam, pageSize: 100 }, signal),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (oldestPage) => oldestPage.next_before ?? undefined,
  })

  // pages[0] is the newest page and later pages are older, so reverse them to get time order.
  const pages = history.data?.pages ?? []
  const messages = [...pages].reverse().flatMap((page) => page.messages)
  const conversations = groupConversations(messages, pages[0]?.conversation_id ?? '')

  // Search what was said, in the messages loaded so far.
  const words = search.trim().toLowerCase()
  const shown = conversations.filter(
    (conversation) => !words || conversation.messages.some((message) => message.content.toLowerCase().includes(words)),
  )
  const selected = shown.find((conversation) => conversation.id === selectedId) ?? shown[0]

  const columns: Column<ConversationSummary>[] = [
    {
      key: 'conversation',
      header: 'Conversation',
      render: (conversation) => (
        <div className={styles.titleCell}>
          <span className={styles.chatTile}>
            <img src="/assets/icons/assistant/chat.png" alt="" width={20} height={20} />
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
            {conversation.isMain && <span className={styles.mainTag}>Main chat</span>}
          </div>
        </div>
      ),
    },
    { key: 'messages', header: 'Messages', width: '110px', render: (conversation) => conversation.messages.length },
    {
      key: 'last',
      header: 'Last activity',
      width: '140px',
      render: (conversation) => formatRelative(conversation.lastActivity),
    },
  ]

  let message: ReactNode = null
  if (history.isPending) message = <p role="status">Loading your conversations…</p>
  else if (history.isError) {
    message = (
      <div role="alert" className={styles.stateBox}>
        <p className={styles.stateTitle}>We couldn’t load your conversations.</p>
        <p>{history.error.message}</p>
        <Button variant="secondary" size="sm" onClick={() => void history.refetch()}>
          Try again
        </Button>
      </div>
    )
  } else if (conversations.length === 0) {
    message = (
      <EmptyState title="No conversations yet." action={<ButtonLink to="/assistant">Ask the assistant</ButtonLink>}>
        <p>What you and the assistant say to each other is kept here.</p>
      </EmptyState>
    )
  } else if (shown.length === 0) {
    message = (
      <EmptyState title={`No conversations match “${search.trim()}”.`}>
        <p>Try other words, clear the search, or load older messages.</p>
      </EmptyState>
    )
  }

  return (
    <>
      <PageHeader
        title="Conversation history"
        subtitle="What you and the assistant said to each other"
        actions={
          <SearchField
            label="Search conversations"
            placeholder="Search words that were said…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        }
      />

      <div className={styles.page}>
        {history.data && !pages.every((page) => page.history_complete) && (
          <Banner tone="info" title="Some older messages may be missing.">
            Conversations from before history was saved could only be partly recovered.
          </Banner>
        )}

        <div className={styles.layout}>
          <div className={styles.listColumn}>
            <DataTable
              caption="Conversations"
              columns={columns}
              rows={shown}
              getRowId={(conversation) => conversation.id}
              getRowLabel={(conversation) => conversation.title}
              onRowClick={(conversation) => setSelectedId(conversation.id)}
              message={message}
            />
            {history.hasNextPage && (
              <div className={styles.more}>
                <Button variant="secondary" disabled={history.isFetchingNextPage} onClick={() => void history.fetchNextPage()}>
                  {history.isFetchingNextPage ? 'Loading…' : 'Load older messages'}
                </Button>
                <span className={styles.moreNote}>Showing the {count(messages.length, 'message')} loaded so far.</span>
              </div>
            )}
          </div>

          {selected && (
            <section className={styles.detail} aria-labelledby={detailTitleId}>
              <div className={styles.detailHead}>
                <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={34} height={34} />
                <h2 id={detailTitleId} className={styles.detailTitle}>
                  {selected.title}
                </h2>
              </div>
              <p className={styles.meta}>
                {formatDateTime(selected.lastActivity)} · {count(selected.messages.length, 'message')}
                {selected.isMain && ' · Main chat'}
              </p>

              <div className={styles.thread}>
                {selected.messages.map((saved) => (
                  <ChatBubble key={saved.id} from={saved.role === 'USER' ? 'user' : 'assistant'} size="sm">
                    {saved.content}
                  </ChatBubble>
                ))}
              </div>

              {selected.isMain && (
                <div className={styles.continue}>
                  <ButtonLink to="/assistant" variant="soft">
                    Continue in the assistant
                  </ButtonLink>
                </div>
              )}
            </section>
          )}
        </div>
      </div>
    </>
  )
}
