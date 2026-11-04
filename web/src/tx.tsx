import { createContext, useCallback, useContext, useState, type ReactNode } from "react";
import { useAccount } from "wagmi";
import { writeContract } from "@wagmi/core";
import { useQueryClient } from "@tanstack/react-query";
import type { Abi, AbiError } from "viem";
import { ABI, ADDR, EXPLORER, chain, wagmiConfig, type Contract } from "./config";
import { client } from "./chain";
import { explain } from "./errors";
import { switchToSepolia } from "./wallet";

export type TxState = { id: number; label: string; phase: "wallet" | "pending" | "confirmed" | "reverted"; hash?: string; note?: string };
type Send = (label: string, c: Contract, fn: string, args?: readonly unknown[]) => Promise<boolean>;
const Ctx = createContext<{ send: Send; txs: TxState[]; busy: (label: string) => boolean; dismiss: (id: number) => void }>(null as any);
let seq = 0;

/** Every custom error of the five game contracts. Villages forwards calls to Army, Clans and
 *  SeedLedger and bubbles their revert data, so a Villages write can revert with an error that only
 *  another contract's ABI defines. Simulating against the union lets viem name it for explain(). */
const GAME_ERRORS: Abi = (() => {
  const seen = new Set<string>();
  const out: AbiError[] = [];
  for (const abi of [ABI.villages, ABI.army, ABI.clans, ABI.ledger, ABI.rules]) {
    for (const x of abi) {
      if (x.type !== "error") continue;
      const sig = `${x.name}(${x.inputs.map((i) => i.type).join(",")})`;
      if (!seen.has(sig)) { seen.add(sig); out.push(x); }
    }
  }
  return out;
})();
export const withGameErrors = (c: Contract): Abi => {
  const own = new Set(ABI[c].filter((x) => x.type === "error").map((x) => (x as AbiError).name));
  return [...ABI[c], ...GAME_ERRORS.filter((x) => !own.has((x as AbiError).name))];
};

export function TxProvider({ children }: { children: ReactNode }) {
  const [txs, setTxs] = useState<TxState[]>([]);
  const { address, chainId } = useAccount();
  const qc = useQueryClient();
  const put = (t: TxState) => setTxs((xs) => [t, ...xs.filter((x) => x.id !== t.id)].slice(0, 6));

  const send: Send = useCallback(async (label, c, fn, args = []) => {
    const id = ++seq;
    if (!address) { put({ id, label, phase: "reverted", note: "Connect a wallet first." }); return false; }
    if (chainId !== chain.id) {
      put({ id, label, phase: "wallet", note: "Switch to Sepolia in your wallet." });
      try { await switchToSepolia(); } catch (e) { put({ id, label, phase: "reverted", note: explain(e) }); return false; }
    }
    const req = { address: (ADDR as any)[c], abi: ABI[c], functionName: fn, args, account: address } as const;
    const sim = { ...req, abi: withGameErrors(c) };
    try {
      put({ id, label, phase: "wallet", note: "Checking the action, then confirm in your wallet." });
      await client.simulateContract(sim as any);
      const hash = await writeContract(wagmiConfig, { ...(req as any), chainId: chain.id });
      put({ id, label, phase: "pending", hash });
      const r = await client.waitForTransactionReceipt({ hash, timeout: 300_000 });
      if (r.status === "success") {
        put({ id, label, phase: "confirmed", hash });
        qc.invalidateQueries();
        return true;
      }
      let note = "The transaction reverted on chain.";
      try { await client.simulateContract({ ...(sim as any), blockNumber: r.blockNumber }); } catch (e) { note = explain(e); }
      put({ id, label, phase: "reverted", hash, note });
    } catch (e) {
      put({ id, label, phase: "reverted", note: explain(e) });
    }
    return false;
  }, [address, chainId, qc]);

  const busy = (label: string) => txs.some((t) => t.label === label && (t.phase === "wallet" || t.phase === "pending"));
  const dismiss = (id: number) => setTxs((xs) => xs.filter((x) => x.id !== id));
  return <Ctx.Provider value={{ send, txs, busy, dismiss }}>{children}</Ctx.Provider>;
}

export const useTx = () => useContext(Ctx);

const PHASE = { wallet: "Waiting for wallet", pending: "Pending", confirmed: "Confirmed", reverted: "Reverted" };

/** Live list of writes and their states, announced politely to screen readers. */
export function TxLog() {
  const { txs, dismiss } = useTx();
  return (
    <section className="txlog" aria-live="polite" aria-label="Transactions">
      {txs.map((t) => (
        <div key={t.id} className={`tx tx-${t.phase}`}>
          <div className="tx-head">
            <strong>{PHASE[t.phase]}</strong>
            <span>{t.label}</span>
            <button className="x" aria-label="Dismiss" onClick={() => dismiss(t.id)}>×</button>
          </div>
          {t.note && <p>{t.note}</p>}
          {t.hash && <a href={`${EXPLORER}/tx/${t.hash}`} target="_blank" rel="noreferrer">View on Etherscan</a>}
        </div>
      ))}
    </section>
  );
}

/** A write button: label stays verb-first; disabled while its own write is in flight. */
export function Act({ label, c, fn, args, disabled, kind = "primary", small, onDone }: {
  label: string; c: Contract; fn: string; args?: readonly unknown[]; disabled?: boolean; kind?: "primary" | "secondary" | "danger"; small?: boolean; onDone?: () => void;
}) {
  const { send, busy } = useTx();
  const b = busy(label);
  return (
    <button className={`btn btn-${kind}${small ? " btn-sm" : ""}`} disabled={disabled || b} aria-busy={b}
      onClick={async () => { if (await send(label, c, fn, args)) onDone?.(); }}>
      {b ? "Working..." : label}
    </button>
  );
}
