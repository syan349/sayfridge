import { describe, expect, it } from 'vitest'
import { photoProblem, photosTooLarge, scaledSize, type PreparedPhoto } from './photos'

const file = (name: string, type: string) => new File(['x'], name, { type })
const photo = (base64Length: number): PreparedPhoto => ({
  image: { image_id: 'id', mime_type: 'image/jpeg', data_base64: 'A'.repeat(base64Length) },
  previewUrl: '',
  name: 'photo.jpg',
})

describe('photos', () => {
  it('accepts JPEG, PNG and WebP, and says what is wrong with anything else', () => {
    expect(photoProblem(file('shelf.jpg', 'image/jpeg'))).toBeNull()
    expect(photoProblem(file('label.png', 'image/png'))).toBeNull()
    expect(photoProblem(file('receipt.webp', 'image/webp'))).toBeNull()
    expect(photoProblem(file('IMG_0001.heic', 'image/heic'))).toBe('“IMG_0001.heic” isn’t a JPEG, PNG or WebP photo.')
    expect(photoProblem(file('list.pdf', 'application/pdf'))).not.toBeNull()
  })

  it('shrinks a large photo to 1600 px on its longest side, keeping its shape', () => {
    expect(scaledSize(4000, 3000)).toEqual({ width: 1600, height: 1200 }) // a 12-megapixel phone photo
    expect(scaledSize(3000, 4000)).toEqual({ width: 1200, height: 1600 })
  })

  it('never enlarges a small photo', () => {
    expect(scaledSize(800, 600)).toEqual({ width: 800, height: 600 })
  })

  it('knows when the photos together are too big for one request', () => {
    expect(photosTooLarge([photo(1_000_000), photo(1_000_000)])).toBe(false)
    expect(photosTooLarge([photo(2_000_000), photo(2_000_000)])).toBe(true)
  })
})
