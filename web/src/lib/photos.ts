// Photos for the assistant. They travel as base64 text inside the JSON request, and
// the hosting platform refuses requests above about 4.5 MB, while a phone photo is
// often 3–8 MB. So every photo is shrunk in the browser first: drawn onto a canvas
// at a smaller size and saved as JPEG. That is still sharp enough to read a label.
import type { AgentImage } from '../api/agent'
import { newIdempotencyKey } from '../api/idempotencyKey'

/** The backend accepts at most 4 photos per message. */
export const MAX_PHOTOS = 4
const ACCEPTED_TYPES = ['image/jpeg', 'image/png', 'image/webp']
/** For <input type="file" accept="…">. */
export const PHOTO_ACCEPT = ACCEPTED_TYPES.join(',')
/** Longest side after shrinking, in pixels. */
const MAX_SIDE = 1600
const JPEG_QUALITY = 0.82
/** Base64 characters allowed for all photos of one message together (about 2.6 MB of image data). */
const MAX_TOTAL_BASE64 = 3_500_000

/** A photo that is ready to send, plus what the page needs to show it. */
export interface PreparedPhoto {
  image: AgentImage
  /** A data: URL of the shrunk photo, for the thumbnail. */
  previewUrl: string
  /** The file's name, used in the thumbnail's description. */
  name: string
}

/** Why this file can't be sent, or null when it can. */
export function photoProblem(file: File): string | null {
  // Phones often save HEIC, which browsers can't read: say what works instead.
  if (!ACCEPTED_TYPES.includes(file.type)) return `“${file.name}” isn’t a JPEG, PNG or WebP photo.`
  return null
}

/** The size to draw at: the same shape, with the longest side at most `maxSide`. Never enlarges. */
export function scaledSize(width: number, height: number, maxSide = MAX_SIDE): { width: number; height: number } {
  const scale = Math.min(1, maxSide / Math.max(width, height))
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) }
}

/** True when these photos together are too big for one request. */
export function photosTooLarge(photos: PreparedPhoto[]): boolean {
  return photos.reduce((total, photo) => total + photo.image.data_base64.length, 0) > MAX_TOTAL_BASE64
}

/** Shrinks one photo and encodes it for the request. Throws if the browser can't read the file. */
export async function preparePhoto(file: File): Promise<PreparedPhoto> {
  const bitmap = await createImageBitmap(file) // also turns the photo the right way up
  const { width, height } = scaledSize(bitmap.width, bitmap.height)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext('2d')
  if (!context) throw new Error('This browser can’t prepare photos.')
  // JPEG has no transparency: put white behind a see-through PNG instead of black.
  context.fillStyle = 'white'
  context.fillRect(0, 0, width, height)
  context.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  const dataUrl = canvas.toDataURL('image/jpeg', JPEG_QUALITY) // "data:image/jpeg;base64,<data>"
  return {
    image: { image_id: newIdempotencyKey(), mime_type: 'image/jpeg', data_base64: dataUrl.slice(dataUrl.indexOf(',') + 1) },
    previewUrl: dataUrl,
    name: file.name,
  }
}
