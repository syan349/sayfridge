import styles from './PanelList.module.css'

/** W01: ticked list of what the web app is good at. */
export function PanelChecklist({ items }: { items: string[] }) {
  return (
    <ul className={styles.list}>
      {items.map((item) => (
        <li key={item} className={styles.item}>
          <span className={styles.check} aria-hidden="true">
            <svg width="14" height="14" viewBox="0 0 24 24">
              <path d="m5 12.5 4.5 4.5L19 7" />
            </svg>
          </span>
          <span className={styles.checkText}>{item}</span>
        </li>
      ))}
    </ul>
  )
}

interface Step {
  title: string
  text: string
}

/** W02: numbered steps; the first one is highlighted as "you are here". */
export function PanelSteps({ steps }: { steps: Step[] }) {
  return (
    <ol className={`${styles.list} ${styles.steps}`}>
      {steps.map((step, index) => (
        <li key={step.title} className={styles.item} aria-current={index === 0 ? 'step' : undefined}>
          <span className={index === 0 ? `${styles.number} ${styles.current}` : styles.number} aria-hidden="true">
            {index + 1}
          </span>
          <span>
            <span className={styles.stepTitle}>{step.title}</span>
            <span className={styles.stepText}>{step.text}</span>
          </span>
        </li>
      ))}
    </ol>
  )
}
