import { useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useReducer, useRef } from 'react'
import {
  chat,
  getConversationState,
  resume,
  type AgentEvent,
  type AgentItem,
  type AgentState,
  type ResumeAnswer,
} from '../../api/agent'
import { ApiError } from '../../api/client'
import { newIdempotencyKey } from '../../api/idempotencyKey'
import { todayLocal } from '../../lib/dates'

export interface ChatMessage {
  id: string
  from: 'user' | 'assistant'
  text: string
}

export interface AssistantState {
  conversationId: string | null
  messages: ChatMessage[]
  /** Everything the assistant proposed or did in this conversation, oldest first. */
  items: AgentItem[]
  /** Set while the assistant waits for the user's answer; resume must send it back. */
  interruptId: string | null
  /** A request is being sent and its answer streamed. */
  busy: boolean
  /** Loading the last conversation after a reload. */
  restoring: boolean
  /** The conversation came back after a reload: the backend doesn't keep the message text. */
  restored: boolean
  error: { message: string; canRetry: boolean } | null
  /** True once text for the current answer started arriving (later text is added to it). */
  replying: boolean
}

type Action =
  | { type: 'request'; userText?: string }
  | { type: 'event'; event: AgentEvent }
  | { type: 'finished' }
  | { type: 'failed'; message: string; canRetry: boolean }
  | { type: 'restoring' }
  | { type: 'restored'; conversationId: string | null; state: AgentState | null }
  | { type: 'reset' }

const initialState: AssistantState = {
  conversationId: null,
  messages: [],
  items: [],
  interruptId: null,
  busy: false,
  restoring: false,
  restored: false,
  error: null,
  replying: false,
}

/** All changes to the conversation happen here, one action at a time. */
function reducer(state: AssistantState, action: Action): AssistantState {
  switch (action.type) {
    case 'request':
      return {
        ...state,
        busy: true,
        replying: false,
        error: null,
        messages: action.userText ? [...state.messages, message(state, 'user', action.userText)] : state.messages,
      }
    case 'event':
      return applyEvent(state, action.event)
    case 'finished':
      return { ...state, busy: false }
    case 'failed':
      return { ...state, busy: false, error: { message: action.message, canRetry: action.canRetry } }
    case 'restoring':
      return { ...state, restoring: true, error: null }
    case 'restored': {
      const saved = action.state
      if (!saved) return { ...state, restoring: false, conversationId: action.conversationId }
      return {
        ...state,
        restoring: false,
        restored: saved.items.length > 0,
        conversationId: action.conversationId,
        items: saved.items,
        interruptId: saved.status === 'WAITING_INPUT' ? (saved.interrupt_id ?? null) : null,
        error:
          saved.status === 'RECOVERABLE'
            ? { message: 'The last answer in this conversation was interrupted. Start a new conversation to go on.', canRetry: false }
            : null,
      }
    }
    case 'reset':
      return initialState
  }
}

/** What each streamed event changes. */
function applyEvent(state: AssistantState, event: AgentEvent): AssistantState {
  switch (event.type) {
    case 'start':
      return { ...state, conversationId: event.conversation_id }
    case 'text_delta': {
      if (!state.replying) {
        return { ...state, replying: true, messages: [...state.messages, message(state, 'assistant', event.delta)] }
      }
      // More words for the answer that is being written: add them to the last bubble.
      const messages = [...state.messages]
      const last = messages[messages.length - 1]
      messages[messages.length - 1] = { ...last, text: last.text + event.delta }
      return { ...state, messages }
    }
    case 'operation_preview':
    case 'operation_result':
      return { ...state, items: upsert(state.items, [event.data]) }
    case 'action_required':
      return { ...state, items: upsert(state.items, event.data.items), interruptId: event.data.interrupt_id }
    case 'done':
      return {
        ...state,
        items: upsert(state.items, event.data.items),
        interruptId: event.data.status === 'WAITING_INPUT' ? (event.data.interrupt_id ?? state.interruptId) : null,
      }
    case 'error':
      return {
        ...state,
        error: { message: 'The assistant stopped before it finished. Try again — nothing will be done twice.', canRetry: true },
      }
  }
}

function message(state: AssistantState, from: ChatMessage['from'], text: string): ChatMessage {
  return { id: `m${state.messages.length}`, from, text }
}

/** Replaces items we already have (same item_id) and adds new ones at the end. */
function upsert(items: AgentItem[], changed: AgentItem[]): AgentItem[] {
  const result = [...items]
  for (const item of changed) {
    const index = result.findIndex((existing) => existing.item_id === item.item_id)
    if (index === -1) result.push(item)
    else result[index] = item
  }
  return result
}

/** The backend's error codes for chat and resume, in words for the user. */
function describeError(error: unknown): { message: string; canRetry: boolean; reload?: boolean } {
  if (!(error instanceof ApiError)) return { message: 'Something went wrong. Please try again.', canRetry: true }
  switch (error.code) {
    case 'AGENT_INPUT_REQUIRED':
      return { message: 'The assistant is waiting for your answer to its proposal first.', canRetry: false, reload: true }
    case 'AGENT_CONVERSATION_BUSY':
      return { message: 'The assistant is still working on your last message. Try again in a moment.', canRetry: true }
    case 'AGENT_RECOVERY_REQUIRED':
      return { message: 'The last answer in this conversation was interrupted. Start a new conversation to go on.', canRetry: false }
    case 'AGENT_UNAVAILABLE':
      return { message: 'The assistant isn’t available right now. Please try again later.', canRetry: true }
    case 'STALE_INTERRUPT':
    case 'STALE_PROPOSAL':
    case 'INVALID_TARGET_SELECTION':
      return { message: 'That proposal changed in the meantime. This is the latest version.', canRetry: false, reload: true }
    case 'VERIFY_OUTCOME_FIRST':
      return { message: 'It isn’t certain the last change was saved. Confirm it first — it won’t be saved twice.', canRetry: false }
    case 'ANSWER_REQUIRED':
      return { message: 'This item needs an answer before it can be confirmed. Use Answer.', canRetry: false }
    default:
      return { message: error.message, canRetry: error.status === 0 || error.status >= 500 }
  }
}

// The conversation id is kept for this browser tab (like the sign-in token), so a
// reload can bring the conversation back with GET /agent/conversations/{id}/state.
function storedConversation(key: string): string | null {
  try {
    return sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function storeConversation(key: string, id: string | null) {
  try {
    if (id) sessionStorage.setItem(key, id)
    else sessionStorage.removeItem(key)
  } catch {
    // Storage blocked: the conversation just won't survive a reload.
  }
}

/** W07's conversation: sending messages, answering proposals, and coming back after a reload. */
export function useAssistant(userId: string) {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(reducer, initialState)
  // The last request, kept so "Try again" can send exactly the same thing (same request_id).
  const retryRef = useRef<(() => void) | null>(null)
  const storageKey = `sayfridge.assistant.${userId}`

  /** Loads what the backend kept about a conversation (after a reload, or when a proposal changed). */
  const restore = useCallback(
    function restore(conversationId: string, signal?: AbortSignal) {
      dispatch({ type: 'restoring' })
      getConversationState(conversationId, signal)
        .then((saved) => dispatch({ type: 'restored', conversationId, state: saved }))
        .catch((error: unknown) => {
          if (signal?.aborted) return
          if (error instanceof ApiError && error.status === 404) {
            // The backend doesn't know it (any more): start fresh.
            storeConversation(storageKey, null)
            dispatch({ type: 'restored', conversationId: null, state: null })
            return
          }
          retryRef.current = () => restore(conversationId)
          dispatch({ type: 'restored', conversationId, state: null })
          dispatch({ type: 'failed', message: 'We couldn’t load your last conversation.', canRetry: true })
        })
    },
    [storageKey],
  )

  // After a reload: bring back the conversation this tab was in.
  useEffect(() => {
    const id = storedConversation(storageKey)
    if (!id) return
    const controller = new AbortController()
    restore(id, controller.signal)
    return () => controller.abort()
  }, [storageKey, restore])

  /** Sends one request and applies its streamed events as they arrive. */
  async function stream(send: (onEvent: (event: AgentEvent) => void) => Promise<void>) {
    let finished = false
    const onEvent = (event: AgentEvent) => {
      if (event.type === 'done' || event.type === 'error') finished = true
      if (event.type === 'start') storeConversation(storageKey, event.conversation_id)
      // The assistant changed the stock: every page showing inventory must reload it.
      if (event.type === 'operation_result' && event.data.status === 'SUCCEEDED') {
        void queryClient.invalidateQueries({ queryKey: ['inventory'] })
        void queryClient.invalidateQueries({ queryKey: ['storage-spaces'] })
        void queryClient.invalidateQueries({ queryKey: ['item-definitions'] })
      }
      dispatch({ type: 'event', event })
    }
    try {
      await send(onEvent)
      if (finished) dispatch({ type: 'finished' })
      else dispatch({ type: 'failed', message: 'The connection was lost before the answer finished.', canRetry: true })
    } catch (error) {
      const problem = describeError(error)
      dispatch({ type: 'failed', message: problem.message, canRetry: problem.canRetry })
      if (problem.reload && state.conversationId) restore(state.conversationId)
    }
  }

  function sendMessage(text: string) {
    // The request_id is made once; a retry sends the same one, so the backend won't do it twice.
    const request = {
      message: text,
      as_of: todayLocal(),
      request_id: newIdempotencyKey(),
      ...(state.conversationId ? { conversation_id: state.conversationId } : {}),
    }
    retryRef.current = () => {
      dispatch({ type: 'request' })
      void stream((onEvent) => chat(request, onEvent))
    }
    dispatch({ type: 'request', userText: text })
    void stream((onEvent) => chat(request, onEvent))
  }

  function answer(responses: ResumeAnswer[], text?: string) {
    if (!state.conversationId || !state.interruptId) return
    const request = {
      conversation_id: state.conversationId,
      interrupt_id: state.interruptId,
      request_id: newIdempotencyKey(),
      responses,
    }
    retryRef.current = () => {
      dispatch({ type: 'request' })
      void stream((onEvent) => resume(request, onEvent))
    }
    dispatch({ type: 'request', userText: text })
    void stream((onEvent) => resume(request, onEvent))
  }

  function startNewConversation() {
    storeConversation(storageKey, null)
    retryRef.current = null
    dispatch({ type: 'reset' })
  }

  return {
    state,
    sendMessage,
    answer,
    retry: () => retryRef.current?.(),
    startNewConversation,
  }
}
