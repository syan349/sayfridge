import { useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useReducer, useRef } from 'react'
import {
  chat,
  getChatHistory,
  getConversationState,
  resume,
  type AgentEvent,
  type AgentItem,
  type AgentState,
  type ChatRequest,
  type ResumeAnswer,
  type SavedMessage,
} from '../../api/agent'
import { ApiError } from '../../api/client'
import { newIdempotencyKey } from '../../api/idempotencyKey'
import { todayLocal } from '../../lib/dates'
import type { PreparedPhoto } from '../../lib/photos'

export interface ChatMessage {
  id: string
  from: 'user' | 'assistant'
  text: string
  /** Photos sent with this message (only known in the tab that sent them). */
  photos?: { url: string; name: string }[]
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
  /** Loading the saved conversation when the page opens. */
  opening: boolean
  /** The backend has older messages than the ones shown (see Conversation history). */
  hasEarlier: boolean
  /** The id of the user's main chat, once the backend has told us. */
  mainId: string | null
  /** True in a side conversation (any conversation that isn't the main chat). */
  side: boolean
  error: { message: string; canRetry: boolean } | null
  /** True once text for the current answer started arriving (later text is added to it). */
  replying: boolean
}

type Action =
  | { type: 'request'; userText?: string; photos?: PreparedPhoto[] }
  | { type: 'event'; event: AgentEvent }
  | { type: 'finished' }
  | { type: 'failed'; message: string; canRetry: boolean }
  | { type: 'opening' }
  | { type: 'opened'; conversationId: string | null; mainId: string | null; state: AgentState | null; saved: SavedMessage[]; hasEarlier: boolean }
  | { type: 'refreshed'; state: AgentState }
  | { type: 'reset'; conversationId: string | null }

const initialState: AssistantState = {
  conversationId: null,
  messages: [],
  items: [],
  interruptId: null,
  busy: false,
  opening: false,
  hasEarlier: false,
  mainId: null,
  side: false,
  error: null,
  replying: false,
}

const INTERRUPTED = 'The last answer in this conversation was interrupted. Start a new conversation to go on.'

/** All changes to the conversation happen here, one action at a time. */
function reducer(state: AssistantState, action: Action): AssistantState {
  const next = applyAction(state, action)
  // "Side" isn't stored separately: it always follows from the two ids.
  return { ...next, side: next.mainId !== null && next.conversationId !== null && next.conversationId !== next.mainId }
}

function applyAction(state: AssistantState, action: Action): AssistantState {
  switch (action.type) {
    case 'request': {
      const photos = action.photos?.map((photo) => ({ url: photo.previewUrl, name: photo.name }))
      const said = action.userText || photos?.length
      return {
        ...state,
        busy: true,
        replying: false,
        error: null,
        messages: said
          ? [...state.messages, { ...message(state, 'user', action.userText ?? ''), ...(photos?.length ? { photos } : {}) }]
          : state.messages,
      }
    }
    case 'event':
      return applyEvent(state, action.event)
    case 'finished':
      return { ...state, busy: false }
    case 'failed':
      return { ...state, busy: false, error: { message: action.message, canRetry: action.canRetry } }
    case 'opening':
      return { ...state, opening: true, error: null }
    case 'opened': {
      // A message sent before the saved chat arrived started its own conversation
      // (the backend makes a new one when no id is sent). Keep it: don't lay the saved chat over it.
      if (state.busy || state.messages.length > 0) return { ...state, opening: false, mainId: action.mainId }
      const saved = action.state
      return {
        ...state,
        opening: false,
        conversationId: action.conversationId,
        mainId: action.mainId,
        hasEarlier: action.hasEarlier,
        // Saved messages keep their own ids; photos aren't kept by the backend, only a note that one was attached.
        messages: action.saved.map((entry) => ({
          id: entry.id,
          from: entry.role === 'USER' ? ('user' as const) : ('assistant' as const),
          text: entry.content,
        })),
        items: saved?.items ?? [],
        interruptId: saved?.status === 'WAITING_INPUT' ? (saved.interrupt_id ?? null) : null,
        error: saved?.status === 'RECOVERABLE' ? { message: INTERRUPTED, canRetry: false } : null,
      }
    }
    case 'refreshed':
      // Only the items change: the error message that explains why stays on screen,
      // and the messages already shown are kept.
      return {
        ...state,
        items: action.state.items,
        interruptId: action.state.status === 'WAITING_INPUT' ? (action.state.interrupt_id ?? null) : null,
      }
    case 'reset':
      // Forget what is on screen, but still know which conversation is the main chat.
      return { ...initialState, mainId: state.mainId, conversationId: action.conversationId }
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
  if (error.status === 413) return { message: 'Those photos are too large to send. Send fewer or smaller photos.', canRetry: false }
  switch (error.code) {
    case 'AGENT_INPUT_REQUIRED':
      return { message: 'The assistant is waiting for your answer to its proposal first.', canRetry: false, reload: true }
    case 'AGENT_CONVERSATION_BUSY':
      return { message: 'The assistant is still working on your last message. Try again in a moment.', canRetry: true }
    case 'AGENT_RECOVERY_REQUIRED':
      return { message: INTERRUPTED, canRetry: false }
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
    case 'IMAGE_ID_CONFLICT':
      return { message: 'Those photos were already sent with another message. Attach them again.', canRetry: false }
    case 'VALIDATION_ERROR':
      // E.g. a photo the backend can't read: it says which problem it found.
      return { message: error.fieldErrors[0]?.msg ?? error.message, canRetry: false }
    default:
      return { message: error.message, canRetry: error.status === 0 || error.status >= 500 }
  }
}

// By default the page continues the user's MAIN chat, which the backend remembers.
// Any other conversation is a side conversation ("New conversation" starts one); its id is
// kept for this browser tab (like the sign-in token), so a reload stays in it.
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
    // Storage blocked: a side conversation just won't survive a reload.
  }
}

/** W07's conversation: opening the saved chat, sending messages and photos, answering proposals. */
export function useAssistant(userId: string) {
  const queryClient = useQueryClient()
  const [state, dispatch] = useReducer(reducer, initialState)
  // The last request, kept so "Try again" can send exactly the same thing (same request_id).
  const retryRef = useRef<(() => void) | null>(null)
  const storageKey = `sayfridge.assistant.${userId}`

  /** Loads the saved chat: its recent messages, and what the assistant is waiting for or has done. */
  const open = useCallback(
    async function open(signal?: AbortSignal) {
      dispatch({ type: 'opening' })
      try {
        const history = await getChatHistory({}, signal) // the main chat's id and state + the latest messages
        let conversationId = storedConversation(storageKey) ?? history.conversation_id
        let saved = history.state
        if (conversationId !== history.conversation_id) {
          try {
            saved = await getConversationState(conversationId, signal)
          } catch (error) {
            if (!(error instanceof ApiError && error.status === 404)) throw error
            // That side conversation was never used: go back to the main chat.
            storeConversation(storageKey, null)
            conversationId = history.conversation_id
          }
        }
        dispatch({
          type: 'opened',
          conversationId,
          mainId: history.conversation_id,
          state: saved,
          // History covers every conversation of the user; show the one being continued.
          saved: history.messages.filter((entry) => entry.conversation_id === conversationId),
          hasEarlier: Boolean(history.next_before),
        })
      } catch (error) {
        if (signal?.aborted) return
        dispatch({ type: 'opened', conversationId: storedConversation(storageKey), mainId: null, state: null, saved: [], hasEarlier: false })
        // A backend without saved history answers 404/405: chatting still works without it.
        if (error instanceof ApiError && (error.status === 404 || error.status === 405)) return
        retryRef.current = () => void open()
        dispatch({ type: 'failed', message: 'We couldn’t load your saved conversation.', canRetry: true })
      }
    },
    [storageKey],
  )

  useEffect(() => {
    const controller = new AbortController()
    void open(controller.signal)
    return () => controller.abort()
  }, [open])

  // Remember a conversation that isn't the main chat, so a reload of this tab stays in it.
  // The main chat needs no remembering: the backend says which one it is.
  useEffect(() => {
    if (state.conversationId && state.conversationId !== state.mainId) storeConversation(storageKey, state.conversationId)
  }, [state.conversationId, state.mainId, storageKey])

  /**
   * After "that proposal changed": fetch the latest items so the card shows the current
   * version, while the message explaining why stays visible.
   */
  function refresh(conversationId: string) {
    getConversationState(conversationId)
      .then((saved) => dispatch({ type: 'refreshed', state: saved }))
      .catch(() => {
        // The error is already on screen; "New conversation" still works.
      })
  }

  /** Sends one request and applies its streamed events as they arrive. */
  async function stream(send: (onEvent: (event: AgentEvent) => void) => Promise<void>) {
    let finished = false
    const onEvent = (event: AgentEvent) => {
      if (event.type === 'done' || event.type === 'error') finished = true
      // The assistant changed the stock: every page showing inventory must reload it.
      if (event.type === 'operation_result' && event.data.status === 'SUCCEEDED') {
        void queryClient.invalidateQueries({ queryKey: ['inventory'] })
        void queryClient.invalidateQueries({ queryKey: ['storage-spaces'] })
        void queryClient.invalidateQueries({ queryKey: ['item-definitions'] })
        void queryClient.invalidateQueries({ queryKey: ['item-categories'] }) // it may have added one
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
      if (problem.reload && state.conversationId) refresh(state.conversationId)
    }
    // The Conversation history page reads the same saved messages: make it fetch them again.
    void queryClient.invalidateQueries({ queryKey: ['agent', 'history'] })
  }

  function sendMessage(text: string, photos: PreparedPhoto[] = []) {
    // The request_id is made once; a retry sends the same one, so the backend won't do it twice.
    const request: ChatRequest = {
      message: text,
      ...(photos.length > 0 ? { images: photos.map((photo) => photo.image) } : {}),
      as_of: todayLocal(),
      request_id: newIdempotencyKey(),
      ...(state.conversationId ? { conversation_id: state.conversationId } : {}),
    }
    retryRef.current = () => {
      dispatch({ type: 'request' })
      void stream((onEvent) => chat(request, onEvent))
    }
    dispatch({ type: 'request', userText: text, photos })
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

  /** Leaves the main chat for a fresh, separate conversation (also the way out of a stuck one). */
  function startNewConversation() {
    const id = newIdempotencyKey() // the backend starts a conversation for an id it hasn't seen
    retryRef.current = null
    dispatch({ type: 'reset', conversationId: id })
  }

  /** From a side conversation back to the main chat and its saved messages. */
  function backToMainChat() {
    storeConversation(storageKey, null)
    retryRef.current = null
    dispatch({ type: 'reset', conversationId: null })
    void open()
  }

  return {
    state,
    sendMessage,
    answer,
    retry: () => retryRef.current?.(),
    startNewConversation,
    backToMainChat,
  }
}
