import { ScopeContext, type Scope } from '../lib/scope'
import { usePersistentState } from '../lib/usePersistentState'

/** Holds the Swing / Long-term / All choice for every page, remembered on this device. */
export default function ScopeProvider({ children }: { children: React.ReactNode }) {
  const [scope, setScope] = usePersistentState<Scope>('scope', 'swing')
  return <ScopeContext.Provider value={{ scope, setScope }}>{children}</ScopeContext.Provider>
}
