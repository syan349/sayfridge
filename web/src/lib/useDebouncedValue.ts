import { useEffect, useState } from 'react'

/**
 * Returns `value`, but only after it has stopped changing for `delayMs`.
 * Used for the search box: we search once the user pauses typing, instead of
 * sending a request for every letter.
 */
export function useDebouncedValue<T>(value: T, delayMs = 300): T {
  const [debounced, setDebounced] = useState(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delayMs)
    return () => clearTimeout(timer) // a new keystroke cancels the previous timer
  }, [value, delayMs])

  return debounced
}
