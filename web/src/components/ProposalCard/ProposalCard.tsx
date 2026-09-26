import { useState, type FormEvent } from 'react'
import type { AgentItem, ResumeAnswer } from '../../api/agent'
import type { InventoryItem } from '../../api/inventory'
import { formatDate } from '../../lib/dates'
import { AiBadge } from '../AiBadge/AiBadge'
import { Button } from '../Button/Button'
import { ItemCell } from '../ItemCell/ItemCell'
import { formatAmount } from '../QuantityCell/formatAmount'
import { StatusPill } from '../StatusPill/StatusPill'
import { TextField } from '../TextField/TextField'
import { describeAgentItem } from './describeAgentItem'
import styles from './ProposalCard.module.css'

const NUMBER_WORDS = ['No', 'One', 'Two', 'Three', 'Four', 'Five']

interface ProposalCardProps {
  /** The items the assistant is waiting on (NEEDS_CONFIRMATION or NEEDS_INPUT). */
  items: AgentItem[]
  /** True while an answer is being sent: the buttons wait. */
  busy: boolean
  /** Sends the answers (POST /agent/resume). `text` is shown in the chat as the user's words. */
  onAnswer: (responses: ResumeAnswer[], text?: string) => void
}

/**
 * What the assistant wants to change, waiting for the user: Confirm, Edit or Cancel.
 * Nothing on this card has changed the stock yet.
 */
export function ProposalCard({ items, busy, onAnswer }: ProposalCardProps) {
  const [editing, setEditing] = useState(false)
  const [message, setMessage] = useState('')

  const toConfirm = items.filter((item) => item.status === 'NEEDS_CONFIRMATION')
  const onlyQuestions = toConfirm.length === 0
  const all = items.length > 1 ? ' all' : ''
  const count = NUMBER_WORDS[items.length] ?? String(items.length)
  const title = `${count} proposed ${items.length === 1 ? 'change' : 'changes'}`

  // Each answer names the item AND its current proposal, so an answer to an old version is refused.
  const answer = (item: AgentItem, decision: ResumeAnswer['decision']): ResumeAnswer => ({
    item_id: item.item_id,
    proposal_id: item.proposal_id,
    decision,
  })

  function sendEdit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const text = message.trim()
    if (!text) return
    // A question is answered ("answer"); a proposal is corrected ("edit"). Both need the text.
    onAnswer(
      items.map((item) => ({ ...answer(item, item.status === 'NEEDS_INPUT' ? 'answer' : 'edit'), message: text })),
      text,
    )
    setEditing(false)
    setMessage('')
  }

  function choose(item: AgentItem, candidate: InventoryItem) {
    onAnswer(
      [{ ...answer(item, 'answer'), selected_inventory_item_id: candidate.id }],
      `The one in ${candidate.storage_space_name}`,
    )
  }

  return (
    <section className={styles.card} aria-label={title}>
      <div className={styles.head}>
        <h2 className={styles.title}>{title}</h2>
        <StatusPill status={onlyQuestions ? 'NEEDS_INPUT' : 'NEEDS_CONFIRMATION'} />
      </div>

      <ul className={styles.rows}>
        {items.map((item) => (
          <ProposalRow key={item.item_id} item={item} busy={busy} onChoose={(candidate) => choose(item, candidate)} />
        ))}
      </ul>

      {editing ? (
        <form className={styles.editForm} onSubmit={sendEdit}>
          <TextField
            label={onlyQuestions ? 'Your answer' : 'What should change?'}
            value={message}
            onChange={(event) => setMessage(event.target.value)}
            maxLength={2000}
            autoFocus
          />
          <div className={styles.buttons}>
            <Button type="submit" size="sm" disabled={busy || !message.trim()}>
              Send
            </Button>
            <Button variant="secondary" size="sm" onClick={() => setEditing(false)}>
              Back
            </Button>
          </div>
        </form>
      ) : (
        <div className={styles.buttons}>
          {toConfirm.length > 0 && (
            <Button disabled={busy} onClick={() => onAnswer(toConfirm.map((item) => answer(item, 'confirm')))}>
              Confirm{toConfirm.length > 1 ? ' all' : ''}
            </Button>
          )}
          <Button variant="secondary" disabled={busy} onClick={() => setEditing(true)}>
            {onlyQuestions ? 'Answer' : 'Edit'}
          </Button>
          <Button variant="secondary" disabled={busy} onClick={() => onAnswer(items.map((item) => answer(item, 'cancel')))}>
            Cancel{all}
          </Button>
        </div>
      )}
    </section>
  )
}

interface ProposalRowProps {
  item: AgentItem
  busy: boolean
  onChoose: (candidate: InventoryItem) => void
}

function ProposalRow({ item, busy, onChoose }: ProposalRowProps) {
  const summary = describeAgentItem(item)
  const detail = [summary.where, summary.change].filter(Boolean).join(' · ')
  const candidates = item.error?.details?.candidates ?? []

  return (
    <li className={styles.row}>
      <div className={styles.rowMain}>
        <ItemCell name={summary.name} detail={detail || undefined} />
        {summary.left && (
          <span className={styles.left}>
            <span className={summary.left.estimated ? `${styles.amount} ${styles.estimated}` : styles.amount}>
              <span aria-hidden="true">→ {summary.left.estimated && '≈ '}</span>
              <span className="visually-hidden">{summary.left.estimated ? 'leaves about ' : 'leaves '}</span>
              {summary.left.text}
            </span>
            {summary.left.estimated && <AiBadge compact />}
          </span>
        )}
      </div>

      {/* The assistant's question, or why it can't go ahead yet. */}
      {item.error && <p className={styles.question}>{item.error.message}</p>}

      {candidates.length > 0 && (
        <div role="group" aria-label="Which one?" className={styles.candidates}>
          {candidates.slice(0, 5).map((candidate) => (
            <Button key={candidate.id} variant="secondary" size="sm" disabled={busy} onClick={() => onChoose(candidate)}>
              {candidate.storage_space_name} · {formatAmount(candidate.display_amount)} {candidate.display_unit}
              {candidate.expiry_date && ` · expires ${formatDate(candidate.expiry_date)}`}
            </Button>
          ))}
        </div>
      )}
    </li>
  )
}
