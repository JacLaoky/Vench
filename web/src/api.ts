import axios from 'axios'

const http = axios.create({ baseURL: '/api' })

export const api = {
  getPortfolio: () => http.get('/portfolio').then(r => r.data),
  getAccount:   () => http.get('/account').then(r => r.data),
  getStats:     (period = 'AT') => http.get('/stats', { params: { period } }).then(r => r.data),
  getJournal:   () => http.get('/journal').then(r => r.data),
  getTrades:    () => http.get('/trades').then(r => r.data),
  getAllTrades:  () => http.get('/all_trades').then(r => r.data),
  getTagStats:  (timeframe = 'AT') => http.get('/tag_stats', { params: { timeframe } }).then(r => r.data),
  getPerformance: (period = 'AT') => http.get('/performance', { params: { period } }).then(r => r.data),
  getSectors:   (type?: string, period = '1D') => http.get('/sectors', { params: { period, ...(type ? { type } : {}) } }).then(r => r.data),
  getMarketBreadth: (period = '1D') => http.get('/market_breadth', { params: { period } }).then(r => r.data),
  getEarningsCalendar: () => http.get('/earnings_calendar').then(r => r.data),
  getMonthlyDetails: (month: string) => http.get('/monthly_details', { params: { month } }).then(r => r.data),
  getDailyNote: (date: string) => http.get(`/daily_notes/${date}`).then(r => r.data),
  saveDailyNote: (date: string, note: string) => http.post(`/daily_notes/${date}`, { note }).then(r => r.data),
  getNote: (tradeId: string) => http.get(`/notes/${tradeId}`).then(r => r.data),
  saveNote: (tradeId: string, note: string) => http.post(`/notes/${tradeId}`, { note }).then(r => r.data),
  sync: () => http.get('/sync').then(r => r.data),
  journalAsk:     (question: string) => http.post('/journal/ask', { question }).then(r => r.data),
  journalReindex: () => http.post('/journal/reindex').then(r => r.data),
}
