import { useCallback, useEffect, useState, type DependencyList, type SetStateAction } from 'react'

interface State<T> { key: string; data: T | null; error: string }

/**
 * Load data for a page: re-runs when deps change, keeps the previous data while reloading,
 * and ignores responses from requests that were superseded (e.g. switching timeframes quickly).
 * `loading` is derived (the latest request key has not resolved yet) rather than set in the effect.
 */
export function useApi<T>(fetcher: () => Promise<T>, deps: DependencyList) {
  const [nonce, setNonce] = useState(0)
  const key = JSON.stringify([...deps, nonce])
  const [state, setState] = useState<State<T>>({ key: '', data: null, error: '' })

  useEffect(() => {
    let current = true
    fetcher()
      .then(data => { if (current) setState({ key, data, error: '' }) })
      .catch(e => {
        if (current) setState(s => ({ key, data: s.data, error: e instanceof Error ? e.message : String(e) }))
      })
    return () => { current = false }
    // the caller's deps (serialised into `key`) decide when to refetch
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  const setData = useCallback((update: SetStateAction<T | null>) => {
    setState(s => ({ ...s, data: typeof update === 'function' ? (update as (p: T | null) => T | null)(s.data) : update }))
  }, [])
  const reload = useCallback(() => setNonce(n => n + 1), [])

  return { data: state.data, setData, error: state.key === key ? state.error : '', loading: state.key !== key, reload }
}
