// Food icons are matched by item name, e.g. "Chicken breast" → chicken_breast.png.
// The list below is exactly the files in public/assets/icons/inventory/, so we
// never ask the server for an icon that doesn't exist.

const FOOD_ICONS = new Set([
  'apple', 'avocado', 'bacon', 'banana', 'basa_fillet', 'beef_tenderloin', 'bell_pepper', 'broccoli',
  'button_mushroom', 'carrot', 'cheese', 'chicken_breast', 'chicken_drumstick', 'crab', 'cucumber', 'eggplant',
  'eggs', 'lamb_chop', 'lemon', 'lettuce', 'milk', 'onion', 'orange', 'pork_chop',
  'potato', 'salmon_fillet', 'shrimp', 'spinach', 'strawberry', 'tomato', 'tuna_steak', 'yogurt',
])

// Common names that don't match a file name exactly.
const ALIASES: Record<string, string> = {
  egg: 'eggs',
  mushroom: 'button_mushroom',
  pepper: 'bell_pepper',
  capsicum: 'bell_pepper',
  salmon: 'salmon_fillet',
  tuna: 'tuna_steak',
  prawn: 'shrimp',
  drumstick: 'chicken_drumstick',
  chicken_drumstick: 'chicken_drumstick',
  yoghurt: 'yogurt',
}

/** "tomatoes" → "tomato", "strawberries" → "strawberry", "bananas" → "banana" */
function singular(word: string): string {
  if (word.endsWith('oes')) return word.slice(0, -2)
  if (word.endsWith('ies')) return `${word.slice(0, -3)}y`
  if (word.endsWith('s') && !word.endsWith('ss')) return word.slice(0, -1)
  return word
}

/** The icon's URL for an item name, or null when there is no matching icon. */
export function foodIconFor(name: string): string | null {
  const key = name.trim().toLowerCase().replace(/[\s-]+/g, '_')
  for (const candidate of [key, singular(key)]) {
    const file = ALIASES[candidate] ?? candidate
    if (FOOD_ICONS.has(file)) return `/assets/icons/inventory/${file}.png`
  }
  return null
}
