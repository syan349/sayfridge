import type { ApiError } from './client'

/**
 * Turns a validation error's field list into one message per field, so a form
 * can show each message under the right input.
 *
 * The backend names the field in `loc`, e.g. ["body", "email"] → "email".
 * Only the first message for each field is kept.
 */
export function fieldMessages(error: ApiError): Record<string, string> {
  const messages: Record<string, string> = {}
  for (const { loc, msg } of error.fieldErrors) {
    const field = loc[loc.length - 1]
    if (typeof field === 'string' && !(field in messages)) {
      messages[field] = msg
    }
  }
  return messages
}
