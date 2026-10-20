import { createContext, useContext } from 'react'

/** Which trades the review pages count: swing (the right-side strategy), long (long-term
 *  holdings) or all. Long-term holdings have no stop or R, so they would skew win rate and R. */
export type Scope = 'swing' | 'long' | 'all'

export const SCOPES: { id: Scope; label: string }[] = [
  { id: 'swing', label: 'Swing' },
  { id: 'long', label: 'Long-term' },
  { id: 'all', label: 'All' },
]

export const ScopeContext = createContext<{ scope: Scope; setScope: (s: Scope) => void }>({
  scope: 'swing',
  setScope: () => {},
})

export const useScope = () => useContext(ScopeContext)
