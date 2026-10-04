/** Common setups and mistakes, offered as one-tap suggestions so tag names stay consistent. */
export const PRESET_TAGS = [
  'Breakout', 'Breakdown', 'Trend Follow', 'Reversal',
  'Earnings', 'Support', 'Resistance', 'Gap Fill',
  'FOMO', 'Revenge', 'Oversize', 'Perfect Entry',
  'Early Exit', 'Late Entry', 'News Play', 'Scalp',
]

const PALETTE = ['#60a5fa', '#c084fc', '#fb923c', '#22d3ee', '#f472b6', '#4ade80', '#f87171', '#94a3b8']

/** The same tag always gets the same colour (stable string hash). */
export function tagColor(tag: string): { background: string; color: string } {
  let h = 0
  for (const ch of tag) h = (h * 31 + ch.charCodeAt(0)) | 0
  const c = PALETTE[Math.abs(h) % PALETTE.length]
  return { background: `${c}26`, color: c }
}
