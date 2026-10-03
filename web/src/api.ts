import axios from 'axios'
import type { Account, HoldingDetail, Position, TagCount, Trade } from './types'

/** Same origin in production (Flask serves the build); the Vite dev server proxies /api. */
export const API_BASE = '/api'

const http = axios.create({ baseURL: API_BASE, timeout: 120_000 })

// Surface the backend's own error message instead of a generic "Request failed with status code"
http.interceptors.response.use(undefined, err => {
  const msg = err.response?.data?.message ?? err.message
  return Promise.reject(new Error(msg))
})

// Untyped endpoints (stats, sectors, …) default to `any`; typed ones pass their response type
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const get = <T = any>(url: string, params?: object) => http.get<T>(url, { params }).then(r => r.data)
const enc = encodeURIComponent

export const api = {
  getPortfolio:        () => get<{ data: Position[] }>('/portfolio'),
  getAccount:          () => get<Account>('/account'),
  getStats:            (period = 'AT') => get('/stats', { period }),
  getJournal:          () => get('/journal'),
  getAllTrades:        () => get<{ data: Trade[] }>('/all_trades'),
  getTags:             () => get<{ tags: TagCount[] }>('/tags'),
  getTagStats:         (timeframe = 'AT') => get('/tag_stats', { timeframe }),
  getPerformance:      (period = 'AT') => get('/performance', { period }),
  getSectors:          (type?: string, period = '1D') => get('/sectors', { period, ...(type ? { type } : {}) }),
  getMarketBreadth:    (period = '1D') => get('/market_breadth', { period }),
  getEarningsCalendar: () => get('/earnings_calendar'),
  getHolding:          (ticker: string, positionId?: string) =>
    get<HoldingDetail>(`/holdings/${enc(ticker)}/trades`, positionId ? { position_id: positionId } : undefined),

  getDailyNote:  (date: string) => get<{ note: string }>(`/daily_notes/${enc(date)}`),
  saveDailyNote: (date: string, note: string) => http.post(`/daily_notes/${enc(date)}`, { note }).then(r => r.data),
  saveNote:      (tradeId: string, note: string) => http.post(`/notes/${enc(tradeId)}`, { note }).then(r => r.data),
  setTags:       (tradeId: string, tags: string[]) =>
    http.patch<{ tags: string[] }>(`/trades/${enc(tradeId)}/tags`, { tags }).then(r => r.data),
  setStop:       (positionId: string, ticker: string, stopPrice: number) =>
    http.patch<{ stop_price: number }>(`/positions/${enc(positionId)}/stop`, { ticker, stop_price: stopPrice })
      .then(r => r.data),

  uploadImage: (tradeId: string, file: File) => {
    const form = new FormData()
    form.append('image', file)
    return http.post<{ filename: string }>(`/upload_image/${enc(tradeId)}`, form).then(r => r.data)
  },
  deleteImage: (tradeId: string, filename: string) =>
    http.delete(`/delete_image/${enc(tradeId)}/${enc(filename)}`).then(r => r.data),
  imageUrl:    (filename: string) => `${API_BASE}/images/${enc(filename)}`,

  sync:              () => http.post('/sync').then(r => r.data),
  journalReindex:    () => http.post('/journal/reindex').then(r => r.data),
  journalClear:      (sessionId: string) => http.post('/journal/session/clear', { session_id: sessionId }).then(r => r.data),
  journalStreamUrl:  `${API_BASE}/journal/ask/stream`,
}
