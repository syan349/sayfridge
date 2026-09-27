import { render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { Sidebar, type SidebarProps } from './Sidebar'

function renderSidebar(props: SidebarProps, path = '/inventory') {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Sidebar {...props} />
    </MemoryRouter>,
  )
}

function linkTargets(list: HTMLElement) {
  return within(list)
    .getAllByRole('link')
    .map((link) => [link.textContent, link.getAttribute('href')])
}

describe('Sidebar', () => {
  it('shows the household menu and marks the current page', () => {
    renderSidebar({ isAdmin: false }, '/inventory')

    expect(linkTargets(screen.getByRole('list', { name: 'Household' }))).toEqual([
      ['Dashboard', '/'],
      ['Inventory', '/inventory'],
      ['Expiry overview', '/expiry'],
      ['Storage spaces', '/spaces'],
      ['AI assistant', '/assistant'],
      ['Conversation log', '/conversations'],
      ['Profile & settings', '/settings'],
    ])
    expect(screen.getByRole('link', { name: 'Inventory' })).toHaveAttribute('aria-current', 'page')
    // "/" must not count as active on every page.
    expect(screen.getByRole('link', { name: 'Dashboard' })).not.toHaveAttribute('aria-current')
  })

  it('keeps Inventory active on an item page', () => {
    renderSidebar({ isAdmin: false }, '/inventory/3f1c2a9e')

    expect(screen.getByRole('link', { name: 'Inventory' })).toHaveAttribute('aria-current', 'page')
  })

  it('hides the administration menu from ordinary users', () => {
    renderSidebar({ isAdmin: false })

    expect(screen.queryByRole('list', { name: 'Administration' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Accounts' })).not.toBeInTheDocument()
  })

  it('shows the administration menu to administrators', () => {
    renderSidebar({ isAdmin: true })

    // Only Accounts: the task ledger and audit pages are left out for now.
    expect(linkTargets(screen.getByRole('list', { name: 'Administration' }))).toEqual([
      ['Accounts', '/admin/accounts'],
    ])
  })

  it('shows a count next to an item when one is given', () => {
    renderSidebar({ isAdmin: false, counts: { inventory: 16 } })

    const inventory = screen.getByRole('link', { name: /Inventory/ })
    expect(within(inventory).getByText('16')).toBeInTheDocument()
  })
})
