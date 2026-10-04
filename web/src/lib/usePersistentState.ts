import { useState } from 'react'

/** useState that remembers its value on this device (a tab, a timeframe, calculator inputs). */
export function usePersistentState<T>(key: string, initial: T) {
  const storageKey = `vench.${key}`
  const [value, setValue] = useState<T>(() => {
    try {
      const raw = localStorage.getItem(storageKey)
      return raw === null ? initial : (JSON.parse(raw) as T)
    } catch {
      return initial
    }
  })

  const update = (next: T) => {
    setValue(next)
    try {
      localStorage.setItem(storageKey, JSON.stringify(next))
    } catch {
      // private mode / storage full: the choice just isn't remembered
    }
  }
  return [value, update] as const
}
