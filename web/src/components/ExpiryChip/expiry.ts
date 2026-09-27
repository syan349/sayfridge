// How an expiry date is shown: a colour ("tone") and a short label, both
// decided by how many days are left. Rules from the design handoff (ExpiryChip).

export type ExpiryTone = 'overdue' | 'urgent' | 'soon' | 'fresh'

/** < 0 overdue · 0–1 urgent · 2–3 soon · more than 3 fresh */
export function expiryTone(daysLeft: number): ExpiryTone {
  if (daysLeft < 0) return 'overdue'
  if (daysLeft <= 1) return 'urgent'
  if (daysLeft <= 3) return 'soon'
  return 'fresh'
}

/** "2 days overdue", "Expires today", "1 day left", "5 days left", "3 weeks", "2 months" */
export function expiryLabel(daysLeft: number): string {
  if (daysLeft < 0) return daysLeft === -1 ? '1 day overdue' : `${-daysLeft} days overdue`
  if (daysLeft === 0) return 'Expires today'
  if (daysLeft === 1) return '1 day left'
  if (daysLeft < 14) return `${daysLeft} days left`
  if (daysLeft < 45) return `${Math.round(daysLeft / 7)} weeks`
  return `${Math.round(daysLeft / 30)} months`
}
