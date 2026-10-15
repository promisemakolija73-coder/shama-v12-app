# Shama V12 Turbo — demo-first rebuild starter

This is a starter implementation, not a guaranteed profitable trading system and not a completed broker certification.

## Architecture
- `public/index.html`: responsive dashboard. It deliberately displays no fabricated account values.
- `server.js`: Node/Express static app, health/status endpoints, authenticated MT5 heartbeat receiver.
- `mt5/ShamaV12_DemoFirst.mq5`: separate MT5 Expert Advisor; trade decisions happen in MT5, not in the website.
- `render.yaml`: Render service definition.

## Deploy on Render
1. Upload/commit these files to the `main` branch of your GitHub repository. Keep `public/index.html` in the `public` folder and the EA in `mt5`.
2. In Render create a **Web Service** from the repository. Runtime Node; build command `npm install`; start command `npm start`; health check `/api/health`.
3. Add environment variable `MT5_BRIDGE_SECRET` with a long random value. Do not put it in source code or the browser. Keep `ALLOW_LIVE_TRADING=false`.
4. Deploy, then visit `/api/health`. It should return `ok: true`.

## MT5 demo setup
1. In MetaTrader 5 desktop, open MetaEditor and create/copy `mt5/ShamaV12_DemoFirst.mq5` as an Expert Advisor, compile, and fix any compiler errors for your broker's MT5 build.
2. Attach to a demo chart. Set `DemoOnly=true`, `AllowLiveTrading=false`, a low `RiskPercent`, and `MaxLots` conservatively.
3. Set `BridgeURL` to your Render URL + `/api/mt5/heartbeat`, and `BridgeSecret` to the same secret configured in Render.
4. MT5: Tools → Options → Expert Advisors → enable WebRequest for listed URL and add the origin `https://shama-v12-app.onrender.com` (use your actual Render host).
5. Confirm Journal/Experts log and `/api/status`. The EA can send account metrics only; the web server does not issue orders.

## Strategy behavior
- EMA crossover entries on a new chart bar; ATR-based stop loss and risk/reward take profit.
- Risk-based sizing, capped lot size, spread filter, one-position default.
- Daily equity loss circuit breaker stops new entries after the configured limit.
- Mild recovery sizing is capped at two steps and 1.3x per step by default. It is still a form of Martingale/recovery and can increase losses. Set `MaxRecoverySteps=0` to disable it.
- Default risk is 0.25% per initial trade; max daily loss default 2%. Broker commissions, slippage, gaps, stop execution, and symbol-specific contract details can still cause losses beyond estimates.

## Important limitations
- The dashboard is not a broker login. Never paste a broker password, MT5 master password, or Deriv API token into the site.
- This starter does not implement Deriv OAuth or a Weltrade API. MT5 obtains broker connection through the MT5 terminal's own logged-in account.
- No vault/bank or withdrawal function exists here. “Vault” is a planning concept only; actual withdrawals must be performed through the broker's official process.
- Bridge secret is shared by the EA and server. Use HTTPS, rotate it if exposed, and never commit it to GitHub. For a multi-user public service, replace the shared-secret model with per-user device credentials and account-level authorization.
- Test in Strategy Tester and on a demo account over different market conditions before considering any live use. Never assume a strategy or deployment works perfectly based only on compiling.
