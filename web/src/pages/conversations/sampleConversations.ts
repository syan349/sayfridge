// SAMPLE DATA ONLY — W08 is not connected (issue #51).
//
// The backend can read back ONE conversation's state (GET /agent/conversations/{id}/state)
// but has no endpoint that lists a user's conversations, and it doesn't return the
// message text. Until it does, the history page shows these made-up conversations,
// with a "Not connected yet" banner, so the page can be built, reviewed and tested.
// When the endpoint exists, replace this file with an api/ function and a useQuery.

import type { InventoryOperation } from '../../api/inventory'

export interface SampleConversation {
  id: string
  title: string
  /** When it last changed (ISO timestamp). */
  lastActivity: string
  /** How the first message came in: typed here, spoken or photographed on the phone. */
  input: 'TEXT' | 'VOICE' | 'PHOTO'
  messages: { from: 'user' | 'assistant'; text: string }[]
  operations: {
    type: InventoryOperation['operation_type']
    item: string
    /** "−0.3 kg", "+2 L", "→ 400 g" */
    change: string
    estimated: boolean
    saved: boolean
  }[]
}

export const SAMPLE_CONVERSATIONS: SampleConversation[] = [
  {
    id: 'sample-1',
    title: 'Tomatoes for lunch',
    lastActivity: '2026-09-22T07:28:00Z',
    input: 'TEXT',
    messages: [
      { from: 'user', text: 'I used two more tomatoes for lunch' },
      { from: 'assistant', text: 'Two tomatoes is about 0.3 kg, so the estimate drops from 10 kg to roughly 9.7 kg.' },
      { from: 'user', text: 'Yes, that’s right' },
      { from: 'assistant', text: 'Done. I have marked it as an estimate rather than a measurement.' },
    ],
    operations: [{ type: 'CONSUME', item: 'Tomatoes', change: '−0.3 kg', estimated: true, saved: true }],
  },
  {
    id: 'sample-2',
    title: 'Weekly shop, typed in',
    lastActivity: '2026-09-21T04:10:00Z',
    input: 'TEXT',
    messages: [
      { from: 'user', text: 'add 2L milk, a dozen eggs and 1 kg of rice' },
      { from: 'assistant', text: 'I’ve added milk (2 L), eggs (12) and rice (1 kg) to the pantry and fridge.' },
    ],
    operations: [
      { type: 'ADD', item: 'Milk', change: '+2 L', estimated: false, saved: true },
      { type: 'ADD', item: 'Eggs', change: '+12 each', estimated: false, saved: true },
      { type: 'ADD', item: 'Rice', change: '+1 kg', estimated: false, saved: true },
    ],
  },
  {
    id: 'sample-3',
    title: 'What can I cook tonight?',
    lastActivity: '2026-09-21T02:45:00Z',
    input: 'VOICE',
    messages: [
      { from: 'user', text: 'what do I have that expires soon' },
      { from: 'assistant', text: 'Spinach and yogurt both expire tomorrow. A spinach and yogurt curry would use both.' },
    ],
    operations: [],
  },
  {
    id: 'sample-4',
    title: 'Half the mince is gone',
    lastActivity: '2026-09-18T06:05:00Z',
    input: 'VOICE',
    messages: [
      { from: 'user', text: 'I used about half the beef mince' },
      { from: 'assistant', text: 'Half of 500 g is about 250 g. I’ve updated the estimate to roughly 250 g left.' },
    ],
    operations: [{ type: 'CONSUME', item: 'Beef mince', change: '−250 g', estimated: true, saved: true }],
  },
  {
    id: 'sample-5',
    title: 'Freezer stocktake',
    lastActivity: '2026-09-16T08:30:00Z',
    input: 'PHOTO',
    messages: [
      { from: 'user', text: 'what is in the garage freezer' },
      { from: 'assistant', text: 'From the photo: about 400 g of peas and 1 L of ice cream. Shall I set those amounts?' },
      { from: 'user', text: 'Set the peas, I’ll check the ice cream' },
    ],
    operations: [
      { type: 'RECONCILE', item: 'Peas', change: '→ 400 g', estimated: false, saved: true },
      { type: 'RECONCILE', item: 'Ice cream', change: '→ 1 L', estimated: false, saved: false },
    ],
  },
]
