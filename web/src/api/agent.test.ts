import { describe, expect, it } from 'vitest'
import { readEventStream, type AgentEvent } from './agent'

/** A response whose body arrives in the given pieces, like a slow network would deliver it. */
function streamedResponse(pieces: Uint8Array[]): Response {
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      pieces.forEach((piece) => controller.enqueue(piece))
      controller.close()
    },
  })
  return new Response(body, { headers: { 'Content-Type': 'text/event-stream' } })
}

describe('readEventStream', () => {
  it('rebuilds events that arrive split across chunks, even in the middle of a character', async () => {
    const text =
      'event: start\ndata: {"type":"start","conversation_id":"c-1","request_id":"r-1"}\n\n' +
      'event: text_delta\ndata: {"type":"text_delta","delta":"About ≈ 9.7 kg left"}\n\n' +
      'event: done\ndata: {"type":"done","status":"COMPLETED","data":{"status":"COMPLETED","items":[]}}\n\n'
    const bytes = new TextEncoder().encode(text)
    // Cut inside the first event, and inside the 3-byte "≈".
    const cut1 = 30
    const cut2 = bytes.indexOf(0xe2) + 1
    const events: AgentEvent[] = []

    await readEventStream(
      streamedResponse([bytes.slice(0, cut1), bytes.slice(cut1, cut2), bytes.slice(cut2)]),
      (event) => events.push(event),
    )

    expect(events.map((event) => event.type)).toEqual(['start', 'text_delta', 'done'])
    expect(events[1]).toEqual({ type: 'text_delta', delta: 'About ≈ 9.7 kg left' })
  })

  it('handles Windows line endings and ignores lines that aren’t data', async () => {
    const text = ': keep-alive\r\n\r\nevent: text_delta\r\ndata: {"type":"text_delta","delta":"Hi"}\r\n\r\n'
    const events: AgentEvent[] = []

    await readEventStream(streamedResponse([new TextEncoder().encode(text)]), (event) => events.push(event))

    expect(events).toEqual([{ type: 'text_delta', delta: 'Hi' }])
  })
})
