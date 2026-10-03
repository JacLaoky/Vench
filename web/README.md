# Vench web

React + TypeScript + Vite + Tailwind front end for the Vench backend. It is the only maintained
client: on a phone, open it in Safari/Chrome and use "Add to Home Screen" (it is a PWA).

```bash
npm install
npm run dev     # http://localhost:5173 — /api is proxied to VITE_API_URL (see vite.config.ts)
npm run build   # outputs dist/, which the Flask backend serves from backend/web_dist
```
