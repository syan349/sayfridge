import { describe, expect, it } from 'vitest'
import { foodIconFor } from './foodIcon'

describe('foodIconFor', () => {
  it.each([
    ['Milk', 'milk'],
    ['Chicken breast', 'chicken_breast'],
    ['Tomatoes', 'tomato'], // plural
    ['Strawberries', 'strawberry'],
    ['  bananas ', 'banana'], // spaces and lower case
    ['Egg', 'eggs'], // alias
    ['Mushrooms', 'button_mushroom'],
  ])('%s → %s.png', (name, file) => {
    expect(foodIconFor(name)).toBe(`/assets/icons/inventory/${file}.png`)
  })

  it('returns null when there is no icon, so the cell shows a letter instead', () => {
    expect(foodIconFor('Beef mince')).toBeNull()
    expect(foodIconFor('Oat milk')).toBeNull()
  })
})
