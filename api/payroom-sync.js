'use strict';

// Cron only: pulls App Store Connect into the private Blob. CRON_SECRET is the
// one credential and a missing one refuses, never runs open.

const crypto = require('node:crypto');
const { quickSales, runSync } = require('./_payroom-lib');

function authorized(req) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const given = crypto.createHash('sha256').update(String(req.headers.authorization || '')).digest();
  const want = crypto.createHash('sha256').update(`Bearer ${secret}`).digest();
  return crypto.timingSafeEqual(given, want);
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (!authorized(req)) {
    res.statusCode = 401;
    return res.end('{"error":"unauthorized"}');
  }
  try {
    // `?quick=1` is the ten-minute check for yesterday's sales report.
    const quick = new URL(req.url || '/', 'http://local').searchParams.get('quick') === '1';
    const result = quick ? await quickSales() : await runSync();
    res.statusCode = 200;
    return res.end(JSON.stringify(result));
  } catch (error) {
    console.error('payroom sync failed', error.message);
    res.statusCode = 502;
    return res.end(JSON.stringify({ error: error.message }));
  }
};
