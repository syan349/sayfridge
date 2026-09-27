/** What other pages can pass to /login through the router's `state`. */
export interface LoginLocationState {
  /** Page to return to after signing in (set by RequireAuth). */
  from?: string
  /** Email to fill in (set after creating an account). */
  email?: string
  /** Message to show above the form. */
  notice?: string
}
