import { Hono } from "hono";
import { sendToAddress, validateAddress, getBalance, deriveAddresses, getDescriptorInfo } from "./rpc";
import { isRateLimited, recordRequest, getWaitSeconds, logDisbursement } from "./limiter";

const app = new Hono();

const FAUCET_AMOUNT = parseFloat(process.env.FAUCET_AMOUNT || "0.001");
const FAUCET_PORT = parseInt(process.env.FAUCET_PORT || "3000", 10);
const DERIVE_RANGE = parseInt(process.env.FAUCET_DERIVE_RANGE || "100", 10);

/** Validate that a string looks like a qpub (starts with Q1 or T4). */
function isValidQpubFormat(qpub: string): boolean {
  return /^(Q1|T4)[A-Za-z0-9]{50,}$/.test(qpub);
}

/**
 * Verify that an address belongs to a qpub by deriving addresses from
 * the qr() descriptor and checking for a match.
 */
async function verifyAddressBelongsToQpub(qpub: string, address: string): Promise<boolean> {
  try {
    // Build the qr() descriptor and get its checksum
    const rawDesc = `qr(${qpub}/0/*)`;
    const info = await getDescriptorInfo(rawDesc);
    const desc = info.descriptor; // descriptor with checksum appended

    // Derive the first N addresses
    const addresses = await deriveAddresses(desc, [0, DERIVE_RANGE - 1]);

    if (addresses.includes(address)) return true;

    // Also check internal (change) path
    const rawDescInt = `qr(${qpub}/1/*)`;
    const infoInt = await getDescriptorInfo(rawDescInt);
    const addressesInt = await deriveAddresses(infoInt.descriptor, [0, DERIVE_RANGE - 1]);

    return addressesInt.includes(address);
  } catch (err) {
    // If the node can't parse the descriptor, the qpub is invalid
    return false;
  }
}

// Serve the faucet page
app.get("/", async (c) => {
  const html = await Bun.file(new URL("pages/index.html", import.meta.url)).text();
  return c.html(html);
});

// Faucet API
app.post("/api/faucet", async (c) => {
  const ip = c.req.header("x-forwarded-for") || c.req.header("x-real-ip") || "unknown";

  // Parse request
  let qpub: string;
  let address: string;
  try {
    const body = await c.req.json();
    qpub = body.qpub;
    address = body.address;
  } catch {
    return c.json({ error: 'Invalid JSON. Expected: { "qpub": "Q1...", "address": "bc1p..." }' }, 400);
  }

  // Validate qpub format
  if (!qpub || typeof qpub !== "string" || !isValidQpubFormat(qpub)) {
    return c.json({ error: "Invalid qpub. Must start with Q1 (mainnet) or T4 (testnet/signet)." }, 400);
  }

  // Validate address
  if (!address || typeof address !== "string") {
    return c.json({ error: "Missing address field." }, 400);
  }

  // Rate limit by qpub
  if (isRateLimited(qpub)) {
    const wait = getWaitSeconds(qpub);
    return c.json({ error: `Rate limited. This qpub can request again in ${wait} seconds.` }, 429);
  }

  // Validate address format
  try {
    const result = await validateAddress(address);
    if (!result.isvalid) {
      return c.json({ error: "Invalid Bitcoin address." }, 400);
    }
  } catch (err: any) {
    return c.json({ error: `Address validation failed: ${err.message}` }, 500);
  }

  // Verify address belongs to the qpub
  const belongs = await verifyAddressBelongsToQpub(qpub, address);
  if (!belongs) {
    return c.json({
      error: `Address does not belong to this qpub. Derive an address using getquantumaddress or getnewaddress bech32m.`,
    }, 400);
  }

  // Send coins
  try {
    const txid = await sendToAddress(address, FAUCET_AMOUNT);
    recordRequest(qpub);
    await logDisbursement({ qpub, address, amount: FAUCET_AMOUNT, txid, ip });
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
console.log(`Rate limit: 1 request per qpub per ${process.env.FAUCET_RATE_LIMIT_SECONDS || 3600}s`);
console.log(`Address derivation range: 0..${DERIVE_RANGE - 1}`);

export default {
  port: FAUCET_PORT,
  fetch: app.fetch,
};
