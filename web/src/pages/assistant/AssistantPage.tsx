import { useEffect, useId, useRef } from 'react'
import { Link } from 'react-router-dom'
import type { AgentItem } from '../../api/agent'
import { useAuth } from '../../auth/AuthContext'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { ChatBubble } from '../../components/ChatBubble/ChatBubble'
import { Composer } from '../../components/Composer/Composer'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { ProposalCard } from '../../components/ProposalCard/ProposalCard'
import { describeAgentItem, isWaiting } from '../../components/ProposalCard/describeAgentItem'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { useAssistant } from './useAssistant'
import styles from './AssistantPage.module.css'

// Starting points for an empty conversation. Clicking one sends it.
const SUGGESTIONS = ['I used 2 eggs', 'What expires in the next 3 days?', 'I bought 2 L of milk for the fridge']

/** W07 — the text assistant: chat on the left, what it proposed and saved on the right. */
export function AssistantPage() {
  const { user } = useAuth()
  const { state, sendMessage, answer, retry, startNewConversation } = useAssistant(user?.id ?? '')
  const messagesRef = useRef<HTMLDivElement>(null)
  const railTitleId = useId()

  // The card only shows while the backend actually waits for an answer (it gave an interrupt_id).
  const waiting = state.interruptId ? state.items.filter(isWaiting) : []
  const thinking = state.busy && !state.replying
  const lastReply = state.messages.findLast((message) => message.from === 'assistant')
  const isEmpty = state.messages.length === 0 && state.items.length === 0 && !state.restoring

  // Keep the newest message in view while the answer streams in.
  useEffect(() => {
    const list = messagesRef.current
    if (list) list.scrollTop = list.scrollHeight
  }, [state.messages, state.items, state.busy])

  return (
    <>
      <PageHeader
        title="AI assistant"
        leading={<img src="/assets/icons/assistant/ai_assistant.png" alt="" width={44} height={44} className={styles.avatar} />}
        subtitle="Tell it what you bought or used, or ask about your food. Text only — voice is on the phone."
        actions={
          <>
            <Button
              variant="secondary"
              icon="/assets/icons/assistant/add.png"
              disabled={state.busy}
              onClick={startNewConversation}
            >
              New conversation
            </Button>
            <ButtonLink to="/conversations" variant="secondary" icon="/assets/icons/assistant/history.png">
              History
            </ButtonLink>
          </>
        }
      />

      <div className={styles.layout}>
        <div className={styles.chat}>
          <div ref={messagesRef} className={styles.messages}>
            {state.restoring ? (
              <p role="status" className={styles.note}>
                Loading your conversation…
              </p>
            ) : (
              <ChatBubble from="assistant">
                Hi {user?.email.split('@')[0]}! Tell me what you bought or used, or ask what’s about to expire. I’ll
                check with you before I change anything I’m not sure about.
              </ChatBubble>
            )}

            {isEmpty && (
              <div className={styles.suggestions} role="group" aria-label="Try saying">
                {SUGGESTIONS.map((text) => (
                  <Button key={text} variant="soft" size="sm" disabled={state.busy} onClick={() => sendMessage(text)}>
                    {text}
                  </Button>
                ))}
              </div>
            )}

            {state.restored && (
              <p className={styles.note}>
                Earlier messages aren’t shown here after a reload. The server may retain conversation history and
                submitted images to resume your session; proposed and saved operations are listed on the right.
              </p>
            )}

            {state.messages.map((message) => (
              <ChatBubble key={message.id} from={message.from}>
                {message.text}
              </ChatBubble>
            ))}

            {thinking && (
              <ChatBubble from="assistant">
                <span className={styles.thinking}>Thinking…</span>
              </ChatBubble>
            )}

            {waiting.length > 0 && (
              <div className={styles.proposal}>
                <ProposalCard items={waiting} busy={state.busy} onAnswer={answer} />
              </div>
            )}

            {state.error && (
              <Banner
                tone="danger"
                role="alert"
                title={state.error.message}
                action={
                  state.error.canRetry && (
                    <Button variant="secondary" size="sm" disabled={state.busy} onClick={retry}>
                      Try again
                    </Button>
                  )
                }
              />
            )}
          </div>

          {/* Screen readers hear "thinking", then the whole answer once it has arrived (not every word). */}
          <p role="status" className="visually-hidden">
            {thinking ? 'The assistant is thinking…' : !state.busy && lastReply ? `Assistant: ${lastReply.text}` : ''}
          </p>

          <div className={styles.composer}>
            <Composer
              onSend={sendMessage}
              sending={state.busy}
              disabled={waiting.length > 0 || state.restoring}
              placeholder={waiting.length > 0 ? 'Answer the proposal above first…' : undefined}
            />
          </div>
        </div>

        <aside className={styles.rail} aria-labelledby={railTitleId}>
          <div>
            <h2 id={railTitleId} className={styles.railTitle}>
              This conversation
            </h2>
            <p className={styles.railText}>What the assistant has proposed, and what it has already saved.</p>
          </div>
          {state.items.length === 0 ? (
            <p className={styles.railEmpty}>Nothing yet. Its proposals and saved changes will show up here.</p>
          ) : (
            <ul className={styles.railList}>
              {/* Newest first */}
              {[...state.items].reverse().map((item) => (
                <RailItem key={item.item_id} item={item} />
              ))}
            </ul>
          )}
          <p className={styles.railNote}>
            Chat messages never change your stock by themselves. Only the operations listed here do.
          </p>
        </aside>
      </div>
    </>
  )
}

function RailItem({ item }: { item: AgentItem }) {
  const summary = describeAgentItem(item)
  const saved = item.result?.inventory
  const title = summary.change ? `${summary.name} — ${summary.change}` : summary.name

  return (
    <li className={isWaiting(item) ? `${styles.railItem} ${styles.railPending}` : styles.railItem}>
      <StatusPill status={item.status} />
      <p className={styles.railItemTitle}>{saved ? <Link to={`/inventory/${saved.id}`}>{title}</Link> : title}</p>
      <p className={styles.railItemText}>{item.error?.message ?? `From “${item.original_text}”`}</p>
    </li>
  )
}
