import { useState, useRef, useEffect } from 'react'
import { api } from '../api'
import { Bot, Send, X, ChevronDown, RotateCcw } from 'lucide-react'

interface Message {
  role: 'user' | 'assistant'
  content: string
}

const SUGGESTIONS = [
  '我最近亏损有什么规律？',
  '胜率最高的是哪个标的？',
  '我在做 earnings play 时的心态怎么样？',
  '找一下我提到过止损的笔记',
]

export default function JournalAI() {
  const [open, setOpen]       = useState(false)
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput]     = useState('')
  const [loading, setLoading] = useState(false)
  const [reindexing, setReindexing] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function send(question: string) {
    if (!question.trim() || loading) return
    const q = question.trim()
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: q }])
    setLoading(true)
    try {
      const res = await api.journalAsk(q)
      setMessages(prev => [...prev, { role: 'assistant', content: res.answer }])
    } catch {
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: '⚠️ 请求失败，请确认后端已设置 DEEPSEEK_API_KEY 并重启服务。',
      }])
    } finally {
      setLoading(false)
    }
  }

  async function reindex() {
    setReindexing(true)
    try {
      await api.journalReindex()
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: '✅ 索引已重建，最新的笔记已经可以搜索了。',
      }])
    } catch {
      setMessages(prev => [...prev, { role: 'assistant', content: '⚠️ 重建索引失败。' }])
    } finally {
      setReindexing(false)
    }
  }

  return (
    <div className="fixed bottom-6 right-6 z-50 flex flex-col items-end gap-2">

      {/* Chat panel */}
      {open && (
        <div className="w-[360px] max-h-[520px] bg-[#12141e] border border-white/10 rounded-2xl shadow-2xl flex flex-col overflow-hidden">

          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-white/10 bg-[#1a1d2e]">
            <div className="flex items-center gap-2">
              <Bot size={16} className="text-violet-400" />
              <span className="text-sm font-medium text-white">Journal AI</span>
              <span className="text-[10px] text-slate-500 bg-white/5 px-2 py-0.5 rounded-full">RAG</span>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={reindex}
                disabled={reindexing}
                title="重建索引（添加新笔记后点击）"
                className="text-slate-500 hover:text-violet-400 transition-colors disabled:opacity-40"
              >
                <RotateCcw size={14} className={reindexing ? 'animate-spin' : ''} />
              </button>
              <button onClick={() => setOpen(false)} className="text-slate-500 hover:text-white">
                <X size={16} />
              </button>
            </div>
          </div>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto p-4 space-y-3 min-h-0">
            {messages.length === 0 && (
              <div className="space-y-3">
                <p className="text-xs text-slate-500 text-center">基于你的交易日志和笔记回答问题</p>
                <div className="grid grid-cols-1 gap-2">
                  {SUGGESTIONS.map(s => (
                    <button
                      key={s}
                      onClick={() => send(s)}
                      className="text-left text-xs text-slate-400 hover:text-violet-300 bg-white/5 hover:bg-violet-500/10 border border-white/5 hover:border-violet-500/30 rounded-lg px-3 py-2 transition-all"
                    >
                      {s}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {messages.map((m, i) => (
              <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[85%] text-xs rounded-xl px-3 py-2 leading-relaxed whitespace-pre-wrap ${
                  m.role === 'user'
                    ? 'bg-violet-600 text-white rounded-br-sm'
                    : 'bg-white/5 text-slate-300 rounded-bl-sm border border-white/5'
                }`}>
                  {m.content}
                </div>
              </div>
            ))}

            {loading && (
              <div className="flex justify-start">
                <div className="bg-white/5 border border-white/5 rounded-xl rounded-bl-sm px-3 py-2">
                  <div className="flex gap-1">
                    {[0,1,2].map(i => (
                      <span key={i} className="w-1.5 h-1.5 bg-violet-400 rounded-full animate-bounce"
                        style={{ animationDelay: `${i * 0.15}s` }} />
                    ))}
                  </div>
                </div>
              </div>
            )}

            <div ref={bottomRef} />
          </div>

          {/* Input */}
          <div className="p-3 border-t border-white/10">
            <div className="flex gap-2 items-end">
              <textarea
                value={input}
                onChange={e => setInput(e.target.value)}
                onKeyDown={e => {
                  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(input) }
                }}
                placeholder="问问你的交易日志..."
                rows={1}
                className="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-xs text-white placeholder-slate-600 resize-none focus:outline-none focus:border-violet-500/50 transition-colors"
              />
              <button
                onClick={() => send(input)}
                disabled={!input.trim() || loading}
                className="p-2 bg-violet-600 hover:bg-violet-500 disabled:opacity-30 disabled:cursor-not-allowed rounded-lg transition-colors flex-shrink-0"
              >
                <Send size={14} className="text-white" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toggle button */}
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-2 bg-violet-600 hover:bg-violet-500 text-white text-sm font-medium px-4 py-2.5 rounded-full shadow-lg shadow-violet-900/40 transition-all hover:scale-105 active:scale-95"
      >
        {open ? <ChevronDown size={16} /> : <Bot size={16} />}
        {!open && 'Journal AI'}
      </button>
    </div>
  )
}
