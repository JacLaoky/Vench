# Vench

[English](#english) · [中文](#中文)

---

## English

Personal trading journal and analytics platform with a Flask REST API, React web dashboard, and Flutter mobile app — connected to a Moomoo brokerage account.

## Features

- **Dashboard** — live portfolio positions with cost basis, market value, and P&L
- **Journal** — daily and monthly trade review with notes, screenshots, and tag filtering
- **Stats** — cumulative P&L chart, last-7-days bar chart, win rate, profit factor
- **Performance** — Sharpe, Sortino, Kelly criterion, max drawdown curve, DOW distribution
- **Sectors / Themes** — ETF heatmap with configurable 1D / 1W / 1M period
- **Market Breadth** — VIX, major indices, sector breadth bars
- **Calculator** — scale-in position sizing and swing trade risk calculator
- **All Trades** — searchable, filterable, sortable full trade history
- **Earnings Calendar** — upcoming earnings for tickers in your trade history and current holdings
- **Journal AI** — floating AI chat widget powered by a Function Calling Agent; two tools: `run_sql` for numeric queries (SQLite `ticker_pnl` view + `position_pnl` table) and `search_notes` for semantic search over diary and trade notes (ChromaDB + multilingual sentence-transformers); SSE streaming with per-tab session memory (DeepSeek API)

## Stack

| Layer | Tech |
|-------|------|
| Backend | Python · Flask · SQLite · yfinance · Moomoo OpenAPI · ChromaDB · DeepSeek API |
| Web | React · TypeScript · Vite · Tailwind CSS v4 · Recharts |
| Mobile | Flutter · Dart |

## Project Structure

```
Vench/
├── backend/
│   ├── app.py            # Flask app — all 25 API routes, PnL engine, rate limiter, caching
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
npm run dev
```

### Flutter

```bash
cd flutter_application_1
flutter pub get
flutter run --dart-define=API_URL=http://your-server:5001
```

## Configuration

All secrets and environment-specific values are loaded from `.env` files, which are excluded from version control via `.gitignore`.

| File | Variables |
|------|-----------|
| `backend/.env` | `MOOMOO_PWD`, `MOOMOO_ACC_ID`, `MOOMOO_HOST`, `MOOMOO_PORT`, `DEEPSEEK_API_KEY` (optional, enables Journal AI) |
| `web/.env` | `VITE_API_URL` |
| Flutter | Pass `API_URL` via `--dart-define` at build time |

## License

MIT

---

## 中文

个人交易日志与分析平台，包含 Flask REST API 后端、React Web 端和 Flutter 移动端，接入富途牛牛券商账户。

## 功能

- **Dashboard** — 实时持仓展示，含成本价、市值、盈亏
- **Journal** — 每日/月度交易复盘，支持备注、截图上传和标签筛选
- **Stats** — 累计盈亏曲线、近7日柱状图、胜率、盈亏比
- **Performance** — Sharpe、Sortino、Kelly 仓位、最大回撤曲线、星期分布
- **Sectors / Themes** — ETF 热力图，支持 1D / 1W / 1M 切换
- **Market Breadth** — VIX、主要指数、板块宽度
- **Calculator** — 分批建仓计算器和波段交易风险计算器
- **All Trades** — 全部历史交易，支持搜索、筛选、排序
- **Earnings Calendar** — 自动获取交易历史和当前持仓中标的的财报日期
- **Journal AI** — 悬浮 AI 聊天窗口，Function Calling Agent 架构；两个工具：`run_sql`（查 SQLite `ticker_pnl` 视图和 `position_pnl` 表）和 `search_notes`（ChromaDB 语义搜索日记和笔记）；SSE 流式输出 + session 对话记忆（DeepSeek API）

## 技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Python · Flask · SQLite · yfinance · 富途 OpenAPI · ChromaDB · DeepSeek API |
| Web 端 | React · TypeScript · Vite · Tailwind CSS v4 · Recharts |
| 移动端 | Flutter · Dart |

## 项目结构

```
Vench/
├── backend/
│   ├── app.py            # Flask 主程序 — 全部 25 个 API 路由、PnL 引擎、限速器、缓存
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
npm run dev
```

### Flutter

```bash
cd flutter_application_1
flutter pub get
flutter run --dart-define=API_URL=http://你的服务器:5001
```

## 环境变量说明

所有密钥和环境相关配置均通过 `.env` 文件注入，已在 `.gitignore` 中排除。

| 文件 | 变量 |
|------|------|
| `backend/.env` | `MOOMOO_PWD`、`MOOMOO_ACC_ID`、`MOOMOO_HOST`、`MOOMOO_PORT`、`DEEPSEEK_API_KEY`（可选，启用 Journal AI） |
| `web/.env` | `VITE_API_URL` |
| Flutter | 通过 `--dart-define=API_URL=...` 在编译时传入 |

## 许可证

MIT
