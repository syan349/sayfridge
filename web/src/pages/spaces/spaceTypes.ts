import type { SpaceType } from '../../api/storageSpaces'

/** The five kinds of space the backend knows, with the words shown for them. */
export const SPACE_TYPES: { type: SpaceType; label: string }[] = [
  { type: 'FRIDGE', label: 'Fridge' },
  { type: 'FREEZER', label: 'Freezer' },
  { type: 'PANTRY', label: 'Pantry' },
  { type: 'WAREHOUSE', label: 'Warehouse' },
  { type: 'OTHER', label: 'Other' },
]

export const spaceTypeLabel = (type: SpaceType) => SPACE_TYPES.find((option) => option.type === type)?.label ?? type
