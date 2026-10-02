import { describe, expect, it } from 'vitest'
import { tableMinWidth } from './tableMinWidth'

describe('tableMinWidth', () => {
  it('adds the fixed widths, room for the name column, and the checkbox column', () => {
    // Like the Accounts table: Account (flexible) + Role 100 + Status 120 + Joined 130 + Actions 220.
    const columns = [{}, { width: '100px' }, { width: '120px' }, { width: '130px' }, { width: '220px' }]

    expect(tableMinWidth(columns, false)).toBe(200 + 570)
    expect(tableMinWidth(columns, true)).toBe(44 + 200 + 570)
  })
})
