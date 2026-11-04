import { createPublicClient, fallback, http, type AbiEvent, type AbiFunction, type Address } from "viem";
import { ABI, ADDR, DEPLOY_BLOCK, RPCS, chain, type Contract } from "./config";

/** Browser-only reads: public Sepolia RPCs with automatic fallback between them. */
export const client = createPublicClient({
  chain,
  transport: fallback(RPCS.map((u) => http(u, { batch: { batchSize: 40, wait: 20 }, retryCount: 1, timeout: 15_000 })), { rank: false }),
});

/** Reads a view. A single struct output comes back from viem as an object; it is returned as an
 *  array in component order so every caller indexes results the same way. */
export async function read<T = any>(c: Contract, functionName: string, args: readonly unknown[] = [], address?: Address): Promise<T> {
  const res = await client.readContract({ address: address ?? (ADDR as any)[c], abi: ABI[c], functionName, args });
  const fn = ABI[c].find((x) => x.type === "function" && x.name === functionName) as AbiFunction | undefined;
  const out = fn?.outputs;
  if (out && out.length === 1 && out[0].type === "tuple" && res && typeof res === "object" && !Array.isArray(res)) {
    return (out[0] as any).components.map((k: { name: string }) => (res as any)[k.name]) as T;
  }
  return res as T;
}
export async function tryRead<T = any>(c: Contract, fn: string, args: readonly unknown[] = [], address?: Address): Promise<T | null> {
  try { return await read<T>(c, fn, args, address); } catch { return null; }
}

export type Ev = { name: string; args: Record<string, any>; block: bigint; tx: string; idx: number };

const replacer = (_: string, v: unknown) => (typeof v === "bigint" ? { $b: v.toString() } : v);
const reviver = (_: string, v: any) => (v && typeof v === "object" && typeof v.$b === "string" ? BigInt(v.$b) : v);
const CACHE_VERSION = "v1";

/** eth_getLogs in chunks from the deployment block, cached in localStorage and extended incrementally. */
export async function events(c: Contract, eventName: string, args?: Record<string, unknown>): Promise<Ev[]> {
  const item = ABI[c].find((x) => x.type === "event" && x.name === eventName) as AbiEvent;
  const key = `sw:${CACHE_VERSION}:${c}:${eventName}:${JSON.stringify(args ?? {})}`;
  let cached: { to: bigint; logs: Ev[] } = { to: DEPLOY_BLOCK - 1n, logs: [] };
  try { const s = localStorage.getItem(key); if (s) cached = JSON.parse(s, reviver); } catch { /* ignore broken cache */ }
  const head = await client.getBlockNumber();
  let from = cached.to + 1n;
  let step = 20_000n;
  const fresh: Ev[] = [];
  while (from <= head) {
    const to = from + step - 1n > head ? head : from + step - 1n;
    try {
      const logs = await client.getLogs({ address: (ADDR as any)[c], event: item, args: args as any, fromBlock: from, toBlock: to, strict: false });
      for (const l of logs as any[]) fresh.push({ name: eventName, args: l.args ?? {}, block: l.blockNumber, tx: l.transactionHash, idx: l.logIndex });
      from = to + 1n;
    } catch (e) {
      if (step <= 500n) throw e;
      step = step / 4n; // the provider refused the range: shrink the chunk and retry
    }
  }
  const all = { to: head, logs: [...cached.logs, ...fresh] };
  try { localStorage.setItem(key, JSON.stringify(all, replacer)); } catch { /* storage full: still return */ }
  return all.logs;
}
