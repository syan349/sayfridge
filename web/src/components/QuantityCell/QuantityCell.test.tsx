import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { makeItem, milk, tomatoes } from '../../test/inventoryFixtures'
import { QuantityCell } from './QuantityCell'

describe('QuantityCell', () => {
  it('shows a confirmed amount plainly, in the user’s unit, without trailing zeros', () => {
    render(<QuantityCell item={milk} />) // display_amount "2.000", unit "L"

    expect(screen.getByText('2 L')).toBeInTheDocument()
    expect(screen.queryByText('AI estimate')).not.toBeInTheDocument()
    expect(screen.queryByText(/confirmed/)).not.toBeInTheDocument()
  })

  it('shows an estimate with ≈, the AI badge and the last confirmed amount', () => {
    const { container } = render(<QuantityCell item={tomatoes} />) // estimated 9.7 kg, confirmed 10 kg

    expect(container).toHaveTextContent('≈ about 9.7 kg') // "about" is for screen readers only
    expect(screen.getByText('AI estimate')).toBeInTheDocument()
    expect(screen.getByText('confirmed 10 kg')).toBeInTheDocument()
  })

  it('says "Possibly used up" for an estimate of zero, and keeps the badge', () => {
    render(<QuantityCell item={makeItem({ ...tomatoes, estimated_current_amount: '0.000', display_amount: '0.000' })} />)

    expect(screen.getByText('Possibly used up')).toBeInTheDocument()
    expect(screen.getByText('AI estimate')).toBeInTheDocument()
  })
})
