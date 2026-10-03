# Vench

[English](#english) · [中文](#中文)

---

## English

Personal trading journal and analytics platform with a Flask REST API and a React web dashboard that installs on a phone as a PWA — connected to a Moomoo brokerage account.

## Features

- **Position engine** — every fill belongs to a position (from flat back to flat): longs, shorts, scale-ins and partial exits; stable position ids; P&L net of every fee; fills dated by fill time
- **Dashboard** — live positions with cost basis, market value and P&L; drill into a position's fills and set its stop
- **Journal** — daily and monthly review with trade notes, daily notes, screenshots and tags; initial vs current stop per position
- **R multiples** — the first stop of a position is locked as its initial stop and defines 1R; R per trade, expectancy in R and an R distribution
- **Stats** — cumulative P&L chart, last-7-days bar chart, win rate and profit factor per closed position
- **Performance** — Sharpe and Sortino on the daily P&L series, Kelly criterion, drawdown curve, day-of-week distribution, R statistics
- **Sectors / Themes** — ETF heatmap with configurable 1D / 1W / 1M period
- **Market Breadth** — VIX, major indices, sector breadth bars
- **Calculator** — scale-in position sizing and swing trade risk calculator
- **All Trades** — searchable, filterable, sortable full trade history
- **Earnings Calendar** — upcoming earnings for tickers in your trade history and current holdings
- **Journal AI** — floating AI chat widget powered by a Function Calling Agent; two tools: `run_sql` for numeric queries over a read-only connection (SQLite `ticker_pnl` view + `position_pnl` table) and `search_notes` for semantic search over diary and trade notes (ChromaDB + a multilingual MiniLM model on ONNX Runtime via fastembed, loaded on demand, incremental indexing); SSE streaming with per-tab session memory (DeepSeek API)

## Stack

| Layer | Tech |
|-------|------|
| Backend | Python · Flask · waitress · SQLite · pandas · yfinance · Moomoo OpenAPI · ChromaDB · fastembed · DeepSeek API |
| Web | React · TypeScript · Vite · Tailwind CSS v4 · Recharts · PWA |
| Mobile | The web app as a PWA (the Flutter app in `flutter_application_1/` is no longer maintained) |

## Project Structure

```
Vench/
├── backend/
│   ├── app.py            # Flask app — API routes, stats, sync, caching; serves the web build
│   ├── positions.py      # Position engine — cycles, per-fill P&L, per-position summaries, R
│   ├── rag.py            # Journal AI — Function Calling Agent, SSE streaming, session memory
│   ├── etfs.json         # Sector / theme ETF definitions
│   └── .env              # Secrets (not committed)
├── web/
│   ├── src/
│   │   ├── pages/        # Dashboard, Journal, Stats, Performance, …
│   │   ├── components/   # Layout, shared UI
│   │   └── api.ts        # Axios client
│   └── .env              # API URL (not committed)
└── flutter_application_1/
    └── lib/              # Mobile app source
```

## Getting Started

### Backend

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

Create `backend/.env`:

```
MOOMOO_PWD=your_password
MOOMOO_ACC_ID=your_account_id
MOOMOO_HOST=127.0.0.1
MOOMOO_PORT=11111
```

```bash
python app.py
```

### Web

```bash
cd web
npm install
```

Create `web/.env`:

```
VITE_API_URL=http://your-server:5001
```

```bash
npm run dev     # the dev server proxies /api to VITE_API_URL
```

### Production

```bash
cd web && npm run build && cp -r dist ../backend/web_dist   # Flask serves the app and the API on one origin
cd ../backend && python app.py                                # waitress on 127.0.0.1:5001
```

The server binds to localhost by default. To reach it from a phone or another machine without
opening a public port, put it behind [Tailscale](https://tailscale.com) (`tailscale serve --bg http://127.0.0.1:5001`
gives an HTTPS URL inside your tailnet), then open that URL on the phone and use **Add to Home Screen**.

### Flutter (not maintained)

The Flutter app predates the web app and is kept for reference only; the web app covers its features
and installs on a phone as a PWA.

## Configuration

All secrets and environment-specific values are loaded from `.env` files, which are excluded from version control via `.gitignore`.

| File | Variables |
|------|-----------|
| `backend/.env` | `MOOMOO_PWD`, `MOOMOO_ACC_ID`, `MOOMOO_HOST`, `MOOMOO_PORT`, `DEEPSEEK_API_KEY` (optional, enables Journal AI) |
| `web/.env` | `VITE_API_URL` (dev proxy target only) |
| Optional backend env | `VENCH_HOST` / `VENCH_PORT` (default `127.0.0.1:5001`), `CORS_ORIGINS` (default `http://localhost:5173`), `VENCH_WEB_DIST`, `RAG_IDLE_UNLOAD_SECS` (default 600) |

## License

MIT

---

## 中文

个人交易日志与分析平台，包含 Flask REST API 后端和可以在手机上安装为 PWA 的 React Web 端，接入富途牛牛券商账户。

## 功能

- **仓位引擎** — 每笔成交归属到一个仓位(从空仓到回到空仓)：做多、做空、加仓、部分止盈都正确处理；仓位 ID 稳定；盈亏扣除全部手续费；按成交时间记录
- **Dashboard** — 实时持仓(成本价、市值、盈亏)，可点开查看仓位的每笔成交并设置止损
- **Journal** — 每日/月度复盘，支持交易笔记、每日笔记、截图和标签；每个仓位区分初始止损和当前止损
- **R 倍数** — 仓位第一次设定的止损锁定为初始止损并定义 1R；每笔交易的 R、R 期望值和 R 分布
- **Stats** — 累计盈亏曲线、近7日柱状图，胜率和盈亏比按已平仓仓位计算
- **Performance** — 基于每日盈亏序列的 Sharpe、Sortino，Kelly 仓位、回撤曲线、星期分布、R 统计
- **Sectors / Themes** — ETF 热力图，支持 1D / 1W / 1M 切换
- **Market Breadth** — VIX、主要指数、板块宽度
- **Calculator** — 分批建仓计算器和波段交易风险计算器
- **All Trades** — 全部历史交易，支持搜索、筛选、排序
- **Earnings Calendar** — 自动获取交易历史和当前持仓中标的的财报日期
- **Journal AI** — 悬浮 AI 聊天窗口，Function Calling Agent 架构；两个工具：`run_sql`（只读连接查 SQLite `ticker_pnl` 视图和 `position_pnl` 表）和 `search_notes`（ChromaDB 语义搜索日记和笔记，多语言 MiniLM 模型经 fastembed 跑在 ONNX Runtime 上，按需加载、增量索引）；SSE 流式输出 + session 对话记忆（DeepSeek API）

## 技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Python · Flask · waitress · SQLite · pandas · yfinance · 富途 OpenAPI · ChromaDB · fastembed · DeepSeek API |
| Web 端 | React · TypeScript · Vite · Tailwind CSS v4 · Recharts · PWA |
| 移动端 | 使用 Web 端的 PWA（`flutter_application_1/` 中的 Flutter 应用已停止维护） |

## 项目结构

```
Vench/
├── backend/
│   ├── app.py            # Flask 主程序 — API 路由、统计、同步、缓存；同时托管 Web 构建产物
│   ├── positions.py      # 仓位引擎 — 仓位周期、逐笔盈亏、仓位汇总、R 倍数
│   ├── rag.py            # Journal AI — Function Calling Agent、SSE 流式输出、session 记忆
│   ├── etfs.json         # 板块 / 主题 ETF 配置
│   └── .env              # 密钥（不提交）
├── web/
│   ├── src/
│   │   ├── pages/        # Dashboard、Journal、Stats、Performance 等
│   │   ├── components/   # Layout 等通用组件
│   │   └── api.ts        # Axios 请求封装
│   └── .env              # API 地址（不提交）
└── flutter_application_1/
    └── lib/              # 移动端源码
```

## 快速开始

### 后端

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

创建 `backend/.env`：

```
MOOMOO_PWD=你的交易密码
MOOMOO_ACC_ID=你的账户ID
MOOMOO_HOST=127.0.0.1
MOOMOO_PORT=11111
```

```bash
python app.py
```

### Web 端

```bash
cd web
npm install
```

创建 `web/.env`：

```
VITE_API_URL=http://你的服务器:5001
```

```bash
npm run dev     # 开发服务器把 /api 代理到 VITE_API_URL
```

### 生产部署

```bash
cd web && npm run build && cp -r dist ../backend/web_dist   # Flask 同源托管网页和 API
cd ../backend && python app.py                                # waitress 监听 127.0.0.1:5001
```

服务默认只监听本机。想从手机或其他机器访问又不开放公网端口，可以用 [Tailscale](https://tailscale.com)
(`tailscale serve --bg http://127.0.0.1:5001` 会在你的私网内提供 HTTPS 地址)，在手机上打开该地址后选择
**添加到主屏幕**。

### Flutter（已停止维护）

Flutter 应用早于 Web 端开发，仅保留作参考；Web 端已覆盖其全部功能，并可在手机上安装为 PWA。

## 环境变量说明

所有密钥和环境相关配置均通过 `.env` 文件注入，已在 `.gitignore` 中排除。

| 文件 | 变量 |
|------|------|
| `backend/.env` | `MOOMOO_PWD`、`MOOMOO_ACC_ID`、`MOOMOO_HOST`、`MOOMOO_PORT`、`DEEPSEEK_API_KEY`（可选，启用 Journal AI） |
| `web/.env` | `VITE_API_URL`（仅开发代理使用） |
| 可选的后端环境变量 | `VENCH_HOST` / `VENCH_PORT`（默认 `127.0.0.1:5001`）、`CORS_ORIGINS`（默认 `http://localhost:5173`）、`VENCH_WEB_DIST`、`RAG_IDLE_UNLOAD_SECS`（默认 600） |

## 许可证

MIT
