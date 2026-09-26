import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ExpiryChip } from './ExpiryChip'

const TODAY = '2026-09-26'

describe('ExpiryChip', () => {
  it.each([
    // expiry date, tone, label
    ['2026-09-24', 'overdue', '2 days overdue'],
    ['2026-09-25', 'overdue', '1 day overdue'],
    ['2026-09-26', 'urgent', 'Expires today'],
    ['2026-09-27', 'urgent', '1 day left'],
    ['2026-09-28', 'soon', '2 days left'],
    ['2026-09-29', 'soon', '3 days left'],
    ['2026-09-30', 'fresh', '4 days left'],
    ['2026-10-15', 'fresh', '3 weeks'],
    ['2026-11-20', 'fresh', '2 months'],
  ])('%s → %s, "%s"', (expiryDate, tone, label) => {
    render(<ExpiryChip expiryDate={expiryDate} today={TODAY} />)

    const chip = screen.getByText(label)
    expect(chip).toHaveAttribute('data-tone', tone)
  })

  it('adds the warning icon only when overdue, and shows the date underneath', () => {
    const { container, rerender } = render(<ExpiryChip expiryDate="2026-09-25" today={TODAY} />)
    expect(container.querySelector('img[src$="warn.png"]')).not.toBeNull()
    expect(screen.getByText('25 Sep 2026')).toBeInTheDocument()

    rerender(<ExpiryChip expiryDate="2026-09-27" today={TODAY} />)
    expect(container.querySelector('img[src$="warn.png"]')).toBeNull()
  })

  it('says "No date" when the item has no expiry date', () => {
    render(<ExpiryChip expiryDate={null} today={TODAY} />)
    expect(screen.getByText('No date')).toBeInTheDocument()
  })
})
