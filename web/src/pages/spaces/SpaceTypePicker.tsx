import type { SpaceType } from '../../api/storageSpaces'
import { SPACE_TYPES } from './spaceTypes'
import styles from './SpacesPage.module.css'

interface SpaceTypePickerProps {
  value: SpaceType
  onChange: (type: SpaceType) => void
  /** Radio group name; must differ between two pickers on the same page. */
  name: string
}

/** "Type": real radio buttons, drawn as cards. */
export function SpaceTypePicker({ value, onChange, name }: SpaceTypePickerProps) {
  return (
    <fieldset className={styles.typePicker}>
      <legend className={styles.legend}>Type</legend>
      <div className={styles.typeGrid}>
        {SPACE_TYPES.map((option) => (
          <label key={option.type} className={styles.typeCard}>
            <input
              type="radio"
              name={name}
              value={option.type}
              checked={value === option.type}
              onChange={() => onChange(option.type)}
            />
            {option.label}
          </label>
        ))}
      </div>
    </fieldset>
  )
}
