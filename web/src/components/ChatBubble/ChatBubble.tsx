import type { ReactNode } from 'react'
import styles from './ChatBubble.module.css'

interface ChatBubbleProps {
  from: 'user' | 'assistant'
  /** sm = the smaller bubbles in the conversation log, without the avatar. */
  size?: 'md' | 'sm'
  children: ReactNode
}

/**
 * One chat message: the assistant's on the left after its avatar, the user's on the
 * right in green. The text is shown as plain text (never as HTML), so nothing the
 * model writes can run as code on the page.
 */
export function ChatBubble({ from, size = 'md', children }: ChatBubbleProps) {
  return (
    <div className={`${styles.row} ${styles[from]} ${styles[size]}`}>
      {from === 'assistant' && size === 'md' && (
        <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={36} height={36} className={styles.avatar} />
      )}
      <div className={styles.bubble}>
        <span className="visually-hidden">{from === 'user' ? 'You: ' : 'Assistant: '}</span>
        {children}
      </div>
    </div>
  )
}
