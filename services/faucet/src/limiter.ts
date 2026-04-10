/** Rate limiter keyed by qpub. Tracks usage in memory with persistent log. */

import { appendFile } from "fs/promises";

const RATE_LIMIT_SECONDS = parseInt(process.env.FAUCET_RATE_LIMIT_SECONDS || "3600", 10);
const LOG_FILE = process.env.FAUCET_LOG_FILE || "faucet.log";

/** In-memory map: qpub → last request timestamp (ms). */
const requests = new Map<string, number>();

export function isRateLimited(qpub: string): boolean {
  const now = Date.now();
  const last = requests.get(qpub);
  return !!last && now - last < RATE_LIMIT_SECONDS * 1000;
}

export function recordRequest(qpub: string): void {
  requests.set(qpub, Date.now());
}

export function getWaitSeconds(qpub: string): number {
  const now = Date.now();
  const last = requests.get(qpub);
  if (!last) return 0;
  return Math.max(0, Math.ceil(RATE_LIMIT_SECONDS - (now - last) / 1000));
}

/** Append a disbursement to the rolling log file. */
export async function logDisbursement(entry: {
  qpub: string;
  address: string;
  amount: number;
  txid: string;
  ip: string;
}) {
  const line = JSON.stringify({
    ...entry,
    timestamp: new Date().toISOString(),
  });
  await appendFile(LOG_FILE, line + "\n").catch(() => {});
}
