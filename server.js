
'use strict';

const express = require('express');
const path = require('path');
const crypto = require('crypto');

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '32kb' }));

app.use(express.static(path.join(__dirname, 'public'), {
  extensions: ['html']
}));

const PORT = Number(process.env.PORT || 10000);
const BRIDGE_SECRET = process.env.MT5_BRIDGE_SECRET || '';
const ALLOW_LIVE_TRADING =
  process.env.ALLOW_LIVE_TRADING === 'true';

let latestStatus = null;
let lastHeartbeatAt = null;

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' ||
      !a || !b) return false;

  const aa = Buffer.from(a);
  const bb = Buffer.from(b);

  return aa.length === bb.length &&
    crypto.timingSafeEqual(aa, bb);
}

function requireBridge(req, res, next) {
  if (!BRIDGE_SECRET) {
    return res.status(503).json({
      ok: false,
      error: 'MT5 bridge is not configured.'
    });
  }

  const supplied =
    req.get('x-shama-bridge-secret') || '';

  if (!safeEqual(supplied, BRIDGE_SECRET)) {
    return res.status(401).json({
      ok: false,
      error: 'Unauthorized bridge.'
    });
  }

  next();
}

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'Shama V12',
    version: '12.1.0',
    mode: 'demo-first',
    bridgeConfigured: Boolean(BRIDGE_SECRET),
    liveTradingAllowedByServer: ALLOW_LIVE_TRADING,
    timestamp: new Date().toISOString()
  });
});

app.get('/api/status', (_req, res) => {
  const ageMs = lastHeartbeatAt
    ? Date.now() - Date.parse(lastHeartbeatAt)
    : null;

  res.json({
    ok: true,
    connected: ageMs !== null && ageMs < 90000,
    lastHeartbeatAt,
    ageMs,
    status: latestStatus,
    notice:
      'MT5 supplies status. This website does not execute trades or hold funds.'
  });
});

app.post('/api/mt5/heartbeat', requireBridge, (req, res) => {
  const b = req.body || {};

  for (const key of [
    'balance',
    'equity',
    'freeMargin',
    'dailyPnl',
    'openPositions'
  ]) {
    if (typeof b[key] !== 'number' ||
        !Number.isFinite(b[key])) {
      return res.status(400).json({
        ok: false,
        error: `Invalid field: ${key}`
      });
    }
  }

  if (
    typeof b.symbol !== 'string' ||
    b.symbol.length > 32 ||
    typeof b.accountMode !== 'string' ||
    !['DEMO', 'REAL', 'UNKNOWN'].includes(b.accountMode)
  ) {
    return res.status(400).json({
      ok: false,
      error: 'Invalid symbol or accountMode.'
    });
  }

  latestStatus = {
    accountMode: b.accountMode,
    symbol: b.symbol,
    balance: b.balance,
    equity: b.equity,
    freeMargin: b.freeMargin,
    dailyPnl: b.dailyPnl,
    openPositions: Math.max(
      0, Math.floor(b.openPositions)
    ),
    eaVersion:
      typeof b.eaVersion === 'string'
        ? b.eaVersion.slice(0, 32)
        : 'unknown',
    liveTradingGuard:
      b.accountMode === 'REAL' && !ALLOW_LIVE_TRADING
        ? 'SERVER_LIVE_TRADING_DISABLED'
        : null
  };

  lastHeartbeatAt = new Date().toISOString();

  res.json({
    ok: true,
    receivedAt: lastHeartbeatAt,
    tradeExecution: 'NOT_SUPPORTED_BY_WEB_SERVER'
  });
});

app.get('*', (req, res, next) => {
  if (req.path.startsWith('/api/')) {
    return res.status(404).json({
      ok: false,
      error: 'API route not found.'
    });
  }

  res.sendFile(
    path.join(__dirname, 'public', 'index.html'),
    err => {
      if (err) next(err);
    }
  );
});

app.use((err, _req, res, _next) => {
  console.error('Request error:', err.message);

  res.status(500).json({
    ok: false,
    error: 'Internal server error.'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(
    `Shama V12 listening on ${PORT}; demo-first mode.`
  );
});
