// The assistant (docs/reference/API_REFERENCE.md §9, backend/app/schemas/agent_actions.py).
//
// Chat and resume don't answer with one JSON body: they answer with a STREAM of
// Server-Sent Events (text/event-stream), so words can appear while the model is
// still writing. EventSource can't be used for this, because it only sends GET
// requests and can't add our bearer token, so we read the stream ourselves with
// fetch() and response.body.getReader().
import { apiFetch, apiStream } from './client'
import type { InventoryItem } from './inventory'

export type AgentAction = 'CREATE_STOCK' | 'ADD' | 'CONSUME' | 'RECONCILE'

export type AgentItemStatus =
  | 'DRAFT'
  | 'READY'
  | 'NEEDS_INPUT' // the assistant has a question (e.g. which milk?)
  | 'NEEDS_CONFIRMATION' // waiting for Confirm / Edit / Cancel
  | 'SUCCEEDED'
  | 'FAILED'
  | 'CANCELLED'

/** What a proposal would do (only the fields the page shows). */
export interface AgentPreview {
  draft: {
    action: AgentAction
    item_query?: string
    quantity_value?: string | null
    quantity_unit?: string | null
    new_definition?: { name: string } | null
    new_space?: { name: string } | null
  }
  /** The stock item before the change; null when a new one would be created. */
  before: InventoryItem | null
  /**
   * The amount left afterwards. A new item has confirmed_current_amount/unit; a change
   * to an existing one has amount/unit, and is_estimated when it's an AI estimate.
   */
  after: {
    amount?: string
    unit?: string
    is_estimated?: boolean
    confirmed_current_amount?: string
    confirmed_current_unit?: string
  } | null
  requires_confirmation: boolean
}

/** One thing the assistant wants to do, e.g. "consume two tomatoes" (AgentItemView). */
export interface AgentItem {
  item_id: string
  item_key: string
  /** Changes every time the proposal changes; answers must name the current one. */
  proposal_id: string
  status: AgentItemStatus
  /** The words it came from: "two more tomatoes". */
  original_text: string
  preview?: AgentPreview | null
  /** A question or a problem. `candidates` lists the batches to choose from. */
  error?: { code: string; message: string; details?: { candidates?: InventoryItem[] } } | null
  /** After it was saved: the stock item as it is now. */
  result?: { inventory?: InventoryItem | null } | null
}

/** AgentConversationState: GET …/state, and the data of the stream's last event. */
export interface AgentState {
  request_id?: string | null
  status: 'COMPLETED' | 'WAITING_INPUT' | 'RECOVERABLE'
  items: AgentItem[]
  /** Set while the assistant waits for an answer; resume must send it back. */
  interrupt_id?: string | null
}

/** Every event type the backend sends (AgentStreamEvent). */
export type AgentEvent =
  | { type: 'start'; conversation_id: string; request_id: string }
  | { type: 'text_delta'; delta: string }
  | { type: 'operation_preview'; data: AgentItem }
  | { type: 'operation_result'; data: AgentItem }
  | { type: 'action_required'; data: { interrupt_id: string; items: AgentItem[] } }
  | { type: 'done'; status: AgentState['status']; data: AgentState }
  | { type: 'error'; code: string; message: string }

/**
 * Reads a text/event-stream body and calls onEvent for each event as soon as it
 * has fully arrived. The stream comes in chunks that don't line up with events,
 * so text is collected in `buffer` until a blank line ends an event:
 *
 *   event: text_delta
 *   data: {"type": "text_delta", "delta": "Two tomatoes is"}
 *   (blank line)
 *
 * The JSON on the "data:" line already contains the type, so the "event:" line is ignored.
 */
export async function readEventStream(response: Response, onEvent: (event: AgentEvent) => void): Promise<void> {
  if (!response.body) return
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    // stream: true keeps a character that was split between two chunks (e.g. "é") intact.
    buffer = (buffer + decoder.decode(value, { stream: true })).replace(/\r\n/g, '\n')
    let end = buffer.indexOf('\n\n')
    while (end !== -1) {
      const event = parseEvent(buffer.slice(0, end))
      if (event) onEvent(event)
      buffer = buffer.slice(end + 2)
      end = buffer.indexOf('\n\n')
    }
  }

  // A last event without the closing blank line.
  const last = parseEvent(buffer + decoder.decode())
  if (last) onEvent(last)
}

function parseEvent(block: string): AgentEvent | null {
  const data = block
    .split('\n')
    .filter((line) => line.startsWith('data:'))
    .map((line) => line.slice('data:'.length).trimStart())
    .join('\n')
  if (!data) return null
  try {
    return JSON.parse(data) as AgentEvent
  } catch {
    return null // not JSON (e.g. a keep-alive comment): skip it
  }
}

/** AgentChatRequest */
export interface ChatRequest {
  message: string
  /** Left out for the first message; the start event says which one was created. */
  conversation_id?: string
  /** Today's date where the user is, like W09. */
  as_of: string
  /** Made by the browser, so a retry of the same message isn't done twice. */
  request_id: string
}

/** POST /agent/chat — send a message and read the streamed answer. */
export async function chat(request: ChatRequest, onEvent: (event: AgentEvent) => void): Promise<void> {
  await readEventStream(await apiStream('/agent/chat', { body: request }), onEvent)
}

/** ResumeAnswer: the user's answer to one waiting item. */
export interface ResumeAnswer {
  item_id: string
  proposal_id: string
  decision: 'confirm' | 'answer' | 'edit' | 'cancel'
  /** Required for answer/edit: what should change. */
  message?: string
  /** Answer by picking one of the candidate batches instead of typing. */
  selected_inventory_item_id?: string
}

/** AgentResumeRequest */
export interface ResumeRequest {
  conversation_id: string
  interrupt_id: string
  request_id: string
  responses: ResumeAnswer[]
}

/** POST /agent/resume — confirm, edit, answer or cancel waiting items; the answer is streamed too. */
export async function resume(request: ResumeRequest, onEvent: (event: AgentEvent) => void): Promise<void> {
  await readEventStream(await apiStream('/agent/resume', { body: request }), onEvent)
}

/** GET /agent/conversations/{id}/state — what was proposed and done (no message text). */
export function getConversationState(conversationId: string, signal?: AbortSignal): Promise<AgentState> {
  return apiFetch<AgentState>(`/agent/conversations/${conversationId}/state`, { signal })
}
