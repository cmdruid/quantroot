/** Bitcoin JSON-RPC client. */

const RPC_URL = process.env.FAUCET_RPC_URL || "http://127.0.0.1:38332";
const RPC_USER = process.env.FAUCET_RPC_USER || "signet";
const RPC_PASS = process.env.FAUCET_RPC_PASS || "signet";
const RPC_WALLET = process.env.FAUCET_RPC_WALLET || "faucet";

let requestId = 0;

async function call(url: string, method: string, params: unknown[] = []) {
  const body = JSON.stringify({
    jsonrpc: "1.0",
    id: ++requestId,
    method,
    params,
  });

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Basic " + btoa(`${RPC_USER}:${RPC_PASS}`),
    },
    body,
  });

  const json = await res.json();

  if (json.error) {
    throw new Error(`RPC error: ${json.error.message} (code ${json.error.code})`);
  }

  return json.result;
}

/** Call a wallet-scoped RPC. */
export function rpcCall(method: string, params: unknown[] = []) {
  return call(`${RPC_URL}/wallet/${RPC_WALLET}`, method, params);
}

/** Call a non-wallet RPC (e.g., deriveaddresses, getdescriptorinfo). */
export function rpcCallBase(method: string, params: unknown[] = []) {
  return call(RPC_URL, method, params);
}

/** Send coins to an address. Returns txid. */
export async function sendToAddress(address: string, amount: number): Promise<string> {
  return rpcCall("sendtoaddress", [address, amount]);
}

/** Validate a Bitcoin address. */
export async function validateAddress(address: string): Promise<{ isvalid: boolean }> {
  return rpcCallBase("validateaddress", [address]);
}

/** Get wallet balance. */
export async function getBalance(): Promise<number> {
  return rpcCall("getbalance");
}

/**
 * Derive addresses from a descriptor.
 * Uses the node's descriptor engine to derive child addresses.
 * @param descriptor - e.g., "qr(Q1.../0/*)"
 * @param range - [start, end] range of child indices
 * @returns array of derived addresses
 */
export async function deriveAddresses(descriptor: string, range: [number, number]): Promise<string[]> {
  return rpcCallBase("deriveaddresses", [descriptor, range]);
}

/**
 * Get descriptor info including the checksum.
 * @param descriptor - raw descriptor string
 * @returns object with descriptor (with checksum), isrange, etc.
 */
export async function getDescriptorInfo(descriptor: string): Promise<{ descriptor: string; isrange: boolean }> {
  return rpcCallBase("getdescriptorinfo", [descriptor]);
}
