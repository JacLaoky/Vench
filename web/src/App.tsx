import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import Journal from './pages/Journal'
import AllTrades from './pages/AllTrades'
import Stats from './pages/Stats'
import Performance from './pages/Performance'
import Sectors from './pages/Sectors'
import MarketBreadth from './pages/MarketBreadth'
import Calendar from './pages/Calendar'
import Calculator from './pages/Calculator'
import TagStats from './pages/TagStats'
import Recap from './pages/Recap'
import Assets from './pages/Assets'
import JournalAI from './components/JournalAI'
import ScopeProvider from './components/ScopeProvider'

export default function App() {
  return (
    <BrowserRouter>
      <ScopeProvider>
      <Layout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/assets" element={<Assets />} />
          <Route path="/journal" element={<Journal />} />
          <Route path="/all-trades" element={<AllTrades />} />
          <Route path="/stats" element={<Stats />} />
          <Route path="/performance" element={<Performance />} />
          <Route path="/tags" element={<TagStats />} />
          <Route path="/recap" element={<Recap />} />
          <Route path="/sectors" element={<Sectors />} />
          <Route path="/breadth" element={<MarketBreadth />} />
          <Route path="/calendar" element={<Calendar />} />
          <Route path="/calculator" element={<Calculator />} />
        </Routes>
        <JournalAI />
      </Layout>
      </ScopeProvider>
    </BrowserRouter>
  )
}
