import type { ItemCategory } from '../api/categories'
import type { InventoryItem } from '../api/inventory'
import type { StorageSpace } from '../api/storageSpaces'
import type { Page } from '../api/types'

export const fridge: StorageSpace = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Fridge',
  type: 'FRIDGE',
  status: 'ACTIVE',
  created_at: '2026-09-01T00:00:00Z',
  updated_at: '2026-09-01T00:00:00Z',
}

export const freezer: StorageSpace = { ...fridge, id: '22222222-2222-4222-8222-222222222222', name: 'Freezer', type: 'FREEZER' }

export const dairy: ItemCategory = { id: '33333333-3333-4333-8333-333333333333', name: 'Dairy', status: 'ACTIVE', sort_order: 1 }
export const vegetables: ItemCategory = { ...dairy, id: '44444444-4444-4444-8444-444444444444', name: 'Vegetables', sort_order: 2 }

/** A confirmed (not estimated) in-stock item in the fridge; override what a test needs. */
export function makeItem(overrides: Partial<InventoryItem>): InventoryItem {
  return {
    id: 'item-id',
    storage_space_id: fridge.id,
    storage_space_name: fridge.name,
    item_definition_id: 'definition-id',
    item_definition_name: 'Item',
    category_id: dairy.id,
    category_name: dairy.name,
    purchase_date: null,
    expiry_date: null,
    notes: null,
    status: 'IN_STOCK',
    initial_amount: '1.000',
    initial_unit: 'each',
    confirmed_current_amount: '1.000',
    confirmed_current_unit: 'each',
    confirmed_at: '2026-09-20T00:00:00Z',
    estimated_current_amount: null,
    estimated_current_unit: null,
    estimated_at: null,
    display_amount: '1.000',
    display_unit: 'each',
    is_estimated: false,
    version: 1,
    created_at: '2026-09-20T00:00:00Z',
    updated_at: '2026-09-20T00:00:00Z',
    ...overrides,
  }
}

export const yogurt = makeItem({
  id: 'aaaaaaaa-0000-4000-8000-000000000001',
  item_definition_name: 'Yogurt',
  display_amount: '200.000',
  display_unit: 'g',
  confirmed_current_amount: '200.000',
  confirmed_current_unit: 'g',
  version: 1,
})

export const milk = makeItem({
  id: 'aaaaaaaa-0000-4000-8000-000000000002',
  item_definition_name: 'Milk',
  display_amount: '2.000',
  display_unit: 'L',
  confirmed_current_amount: '2.000',
  confirmed_current_unit: 'L',
  version: 3,
})

export const tomatoes = makeItem({
  id: 'aaaaaaaa-0000-4000-8000-000000000003',
  item_definition_name: 'Tomatoes',
  category_id: vegetables.id,
  category_name: vegetables.name,
  confirmed_current_amount: '10.000',
  confirmed_current_unit: 'kg',
  estimated_current_amount: '9.700',
  estimated_current_unit: 'kg',
  display_amount: '9.700',
  display_unit: 'kg',
  is_estimated: true,
  version: 2,
})

export function page<T>(items: T[], total = items.length): Page<T> {
  return { items, total, page: 1, page_size: 20 }
}
