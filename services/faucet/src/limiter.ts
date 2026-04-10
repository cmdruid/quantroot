/** In-memory IP-based rate limiter. Resets on restart. */

const RATE_LIMIT_SECONDS = parseInt(process.env.FAUCET_RATE_LIMIT_SECONDS || "3600", 10);

const requests = new Map<string, number>();

export function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const last = requests.get(ip);

  if (last && now - last < RATE_LIMIT_SECONDS * 1000) {
    return true;
  }

  return false;
}

export function recordRequest(ip: string): void {
  requests.set(ip, Date.now());
}

export function getWaitSeconds(ip: string): number {
  const now = Date.now();
  const last = requests.get(ip);

  if (!last) return 0;

  const elapsed = (now - last) / 1000;
  const remaining = RATE_LIMIT_SECONDS - elapsed;

  return Math.max(0, Math.ceil(remaining));
}
