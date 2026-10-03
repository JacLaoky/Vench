import { useRef, useState } from 'react'
import { ImagePlus, Trash2 } from 'lucide-react'
import { api } from '../api'

export default function Screenshots({ tradeId, images, onChange }: {
  tradeId: string
  images: string[]
  onChange: (images: string[]) => void
}) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [zoom, setZoom] = useState<string | null>(null)

  async function upload(files: FileList | null) {
    if (!files?.length) return
    setBusy(true)
    setError('')
    const added: string[] = []
    try {
      for (const file of Array.from(files)) {
        added.push((await api.uploadImage(tradeId, file)).filename)
      }
    } catch (e) {
      setError(`Upload failed: ${(e as Error).message}`)
    } finally {
      if (added.length) onChange([...images, ...added])
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function remove(filename: string) {
    setError('')
    try {
      await api.deleteImage(tradeId, filename)
      onChange(images.filter(f => f !== filename))
    } catch (e) {
      setError(`Delete failed: ${(e as Error).message}`)
    }
  }

  return (
    <div>
      <div className="flex gap-2 flex-wrap">
        {images.map(f => (
          <div key={f} className="relative group">
            <img src={api.imageUrl(f)} alt="" loading="lazy" onClick={() => setZoom(f)}
              className="w-24 h-24 object-cover rounded-lg border border-white/10 cursor-zoom-in" />
            <button onClick={() => remove(f)} aria-label="Delete screenshot"
              className="absolute top-1 right-1 p-1 rounded-md bg-black/60 text-slate-300 hover:text-red-400 sm:opacity-0 sm:group-hover:opacity-100">
              <Trash2 size={12} />
            </button>
          </div>
        ))}
        <button onClick={() => fileRef.current?.click()} disabled={busy}
          className="w-24 h-24 rounded-lg border border-dashed border-white/15 text-slate-500 hover:text-violet-400 hover:border-violet-500/50 flex flex-col items-center justify-center gap-1 text-xs disabled:opacity-50">
          <ImagePlus size={18} />
          {busy ? 'Uploading…' : 'Add'}
        </button>
        <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" multiple hidden
          onChange={e => upload(e.target.files)} />
      </div>
      {error && <p className="text-xs text-red-400 mt-1">{error}</p>}
      {zoom && (
        <div className="fixed inset-0 z-[60] bg-black/80 flex items-center justify-center p-4" onClick={() => setZoom(null)}>
          <img src={api.imageUrl(zoom)} alt="" className="max-w-full max-h-full rounded-lg" />
        </div>
      )}
    </div>
  )
}
