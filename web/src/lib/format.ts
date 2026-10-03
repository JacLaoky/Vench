export const usd = (n: number) =>
  `$${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export const signedUsd = (n: number) => `${n >= 0 ? '+' : '-'}${usd(n)}`

export const pnlColor = (n: number) => (n >= 0 ? 'text-emerald-400' : 'text-red-400')

export const fmtR = (r: number | null | undefined) =>
  r === null || r === undefined ? '—' : `${r >= 0 ? '+' : ''}${r.toFixed(2)}R`

export const rColor = (r: number | null | undefined) =>
  r === null || r === undefined ? 'text-slate-500' : r >= 0 ? 'text-emerald-400' : 'text-red-400'
