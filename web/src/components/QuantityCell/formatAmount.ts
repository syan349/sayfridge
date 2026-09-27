// The backend sends amounts as decimal strings with three places ("2.000").
// We tidy them as text, never via parseFloat, so no precision is ever lost.

/** "2.000" → "2", "9.700" → "9.7", "0.250" → "0.25" */
export function formatAmount(amount: string): string {
  return amount.includes('.') ? amount.replace(/\.?0+$/, '') : amount
}

/** "0", "0.000" → true */
export function isZeroAmount(amount: string): boolean {
  return /^0+(\.0+)?$/.test(amount)
}
