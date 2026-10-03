import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../auth/AuthContext'
import { loadReminders, storeReminders, type ReminderPreferences } from './reminders'

/**
 * The signed-in user's reminder preferences, shared by every screen that uses them
 * (sidebar count, dashboard, expiry overview, profile). They are kept in the React
 * Query cache, so changing them on the profile page updates the other screens at once.
 */
export function useReminders() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const userId = user?.id ?? ''
  const queryKey = ['reminders', userId]

  const { data: reminders } = useQuery({
    queryKey,
    queryFn: () => loadReminders(userId),
    initialData: () => loadReminders(userId), // read from the browser straight away: no loading state
    staleTime: Infinity,
  })

  function saveReminders(changes: Partial<ReminderPreferences>) {
    const next = { ...reminders, ...changes }
    storeReminders(userId, next)
    queryClient.setQueryData(queryKey, next)
  }

  return { reminders, saveReminders }
}
