import { useEffect, useState } from 'react'
import { X } from 'lucide-react'
import { api } from '../api'
import { PRESET_TAGS, tagColor } from '../lib/tags'

// Tag suggestions, shared by every editor on the page and fetched once
let knownTagsCache: string[] | null = null
function rememberTags(tags: string[]): string[] {
  knownTagsCache = [...new Set([...(knownTagsCache ?? []), ...tags])]
  return knownTagsCache
}

export default function TagEditor({ tradeId, tags, onChange }: {
  tradeId: string
  tags: string[]
  onChange: (tags: string[]) => void
}) {
  const [input, setInput] = useState('')
  const [known, setKnown] = useState<string[]>(knownTagsCache ?? [])
  const [error, setError] = useState('')

  useEffect(() => {
    if (knownTagsCache) return
    api.getTags()
      .then(r => setKnown(rememberTags(r.tags.map(t => t.tag))))
      .catch(() => {})
  }, [])

  async function save(next: string[]) {
    setError('')
    try {
      const res = await api.setTags(tradeId, next)
      onChange(res.tags)
      setKnown(rememberTags(res.tags))
    } catch (e) {
      setError(`Save failed: ${(e as Error).message}`)
    }
  }

  function add(tag: string) {
    const t = tag.trim()
    setInput('')
    if (t && !tags.includes(t)) save([...tags, t])
  }

  // tags you've already used first, then the presets; narrowed as you type
  const pool = [...new Set([...known, ...PRESET_TAGS])]
  const suggestions = pool.filter(t => !tags.includes(t) && t.toLowerCase().includes(input.trim().toLowerCase())).slice(0, 10)

  return (
    <div>
      <div className="flex gap-1.5 flex-wrap items-center">
        {tags.map(tag => (
          <span key={tag} className="flex items-center gap-1 text-xs pl-2 pr-1 py-0.5 rounded-full" style={tagColor(tag)}>
            {tag}
            <button onClick={() => save(tags.filter(t => t !== tag))} className="hover:text-white" aria-label={`Remove ${tag}`}>
              <X size={11} />
            </button>
          </span>
        ))}
        <input value={input} onChange={e => setInput(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); add(input) } }}
          placeholder="+ tag"
          className="w-24 bg-transparent border-b border-line text-xs text-white placeholder-slate-600 focus:outline-none focus:border-violet-500 py-0.5" />
      </div>
      {suggestions.length > 0 && (
        <div className="flex gap-1 flex-wrap mt-2">
          {suggestions.map(t => (
            <button key={t} onClick={() => add(t)}
              className="text-[11px] px-2 py-0.5 rounded-full bg-white/5 text-slate-500 hover:text-violet-300">
              {t}
            </button>
          ))}
        </div>
      )}
      {error && <p className="text-xs text-red-400 mt-1">{error}</p>}
    </div>
  )
}
