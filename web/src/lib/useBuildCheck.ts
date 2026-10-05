import { useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'

const CHECK_EVERY_MS = 5 * 60 * 1000

/** Entry script of the build this tab is running, e.g. "/assets/index-CKOoGrxE.js". */
function runningEntry(): string | null {
  const el = document.querySelector<HTMLScriptElement>('script[type="module"][src*="/assets/"]')
  return el ? new URL(el.src).pathname : null
}

/** Entry script of the build the server is serving now. */
async function servedEntry(): Promise<string | null> {
  const res = await fetch('/', { cache: 'no-store' })
  if (!res.ok) return null
  const m = (await res.text()).match(/<script[^>]+type="module"[^>]+src="([^"]+)"/)
  return m ? new URL(m[1], location.origin).pathname : null
}

/**
 * A tab left open keeps running the old bundle against the new API. Check for a newer build when
 * the tab comes back into view and every few minutes; once one is found, reload on the next
 * navigation so the switch happens between pages, never in the middle of one.
 */
export function useBuildCheck() {
  const stale = useRef(false)
  const { pathname } = useLocation()

  useEffect(() => {
    const running = runningEntry()
    if (!running) return   // dev server: no hashed entry to compare
    const check = () => {
      if (stale.current || document.visibilityState !== 'visible') return
      servedEntry().then(served => { if (served && served !== running) stale.current = true }).catch(() => {})
    }
    const timer = setInterval(check, CHECK_EVERY_MS)
    document.addEventListener('visibilitychange', check)
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', check) }
  }, [])

  useEffect(() => {
    if (stale.current) location.reload()
  }, [pathname])
}
