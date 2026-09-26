import type { SpaceType } from '../../api/storageSpaces'
import styles from './SpaceIcon.module.css'

// Simple line drawings for each kind of space (the mobile app has no icons for these).
const PATHS: Record<SpaceType, string[]> = {
  FRIDGE: ['M7 3h10a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z', 'M6 10h12', 'M9 6v2', 'M9 13v3'],
  FREEZER: ['M12 3v18', 'M4.2 7.5l15.6 9', 'M19.8 7.5l-15.6 9', 'M10 4.5 12 6l2-1.5', 'M10 19.5 12 18l2 1.5'],
  PANTRY: ['M4 4h16v16H4Z', 'M4 10h16', 'M4 15h16', 'M8 7h2', 'M14 12.5h2'],
  WAREHOUSE: ['M3 10 12 4l9 6v10H3Z', 'M7 20v-6h10v6', 'M7 17h10'],
  OTHER: ['M4 8l8-4 8 4v8l-8 4-8-4Z', 'M4 8l8 4 8-4', 'M12 12v8'],
}

/** A tile with a drawing of the space type (fridge, snowflake, shelves…). Decorative. */
export function SpaceIcon({ type }: { type: SpaceType }) {
  return (
    <span className={`${styles.tile} ${styles[type.toLowerCase()] ?? ''}`} aria-hidden="true">
      <svg width="20" height="20" viewBox="0 0 24 24">
        {PATHS[type].map((d) => (
          <path key={d} d={d} />
        ))}
      </svg>
    </span>
  )
}
