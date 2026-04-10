import { Hono } from "hono";
import { serveStatic } from "hono/bun";
import { sendToAddress, validateAddress, getBalance } from "./rpc";
import { isRateLimited, recordRequest, getWaitSeconds } from "./limiter";

const app = new Hono();

const FAUCET_AMOUNT = parseFloat(process.env.FAUCET_AMOUNT || "0.001");
const FAUCET_PORT = parseInt(process.env.FAUCET_PORT || "3000", 10);

// Serve the faucet page
app.get("/", async (c) => {
  const html = await Bun.file(new URL("pages/index.html", import.meta.url)).text();
  return c.html(html);
});

// Faucet API
app.post("/api/faucet", async (c) => {
  const ip = c.req.header("x-forwarded-for") || c.req.header("x-real-ip") || "unknown";

  // Rate limit
  if (isRateLimited(ip)) {
    const wait = getWaitSeconds(ip);
    return c.json({ error: `Rate limited. Try again in ${wait} seconds.` }, 429);
  }

  // Parse request
  let address: string;
  try {
    const body = await c.req.json();
    address = body.address;
  } catch {
    return c.json({ error: "Invalid JSON. Expected: { \"address\": \"bc1...\" }" }, 400);
  }

  if (!address || typeof address !== "string") {
    return c.json({ error: "Missing address field." }, 400);
  }

  // Validate address
  try {
    const result = await validateAddress(address);
    if (!result.isvalid) {
      return c.json({ error: "Invalid Bitcoin address." }, 400);
    }
  } catch (err: any) {
    return c.json({ error: `Address validation failed: ${err.message}` }, 500);
  }

  // Send coins
  try {
    const txid = await sendToAddress(address, FAUCET_AMOUNT);
    recordRequest(ip);
    return c.json({ txid, amount: FAUCET_AMOUNT });
  } catch (err: any) {
    return c.json({ error: `Send failed: ${err.message}` }, 500);
  }
});

// Health check
app.get("/api/health", async (c) => {
  try {
    const balance = await getBalance();
    return c.json({ status: "ok", balance });
  } catch (err: any) {
    return c.json({ status: "error", error: err.message }, 500);
  }
});

console.log(`Quantroot Faucet running on http://localhost:${FAUCET_PORT}`);
console.log(`Dispensing ${FAUCET_AMOUNT} BTC per request`);

export default {
  port: FAUCET_PORT,
  fetch: app.fetch,
};
