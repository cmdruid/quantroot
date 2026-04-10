/** Bitcoin JSON-RPC client. */

const RPC_URL = process.env.FAUCET_RPC_URL || "http://127.0.0.1:38332";
const RPC_USER = process.env.FAUCET_RPC_USER || "signet";
const RPC_PASS = process.env.FAUCET_RPC_PASS || "signet";
const RPC_WALLET = process.env.FAUCET_RPC_WALLET || "faucet";

let requestId = 0;

export async function rpcCall(method: string, params: unknown[] = []) {
  const url = `${RPC_URL}/wallet/${RPC_WALLET}`;
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

/** Send coins to an address. Returns txid. */
export async function sendToAddress(address: string, amount: number): Promise<string> {
  return rpcCall("sendtoaddress", [address, amount]);
}

/** Validate a Bitcoin address. */
export async function validateAddress(address: string): Promise<{ isvalid: boolean }> {
  return rpcCall("validateaddress", [address]);
}

/** Get wallet balance. */
export async function getBalance(): Promise<number> {
  return rpcCall("getbalance");
}
