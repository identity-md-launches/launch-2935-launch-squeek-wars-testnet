import type { ReactNode } from "react";
import type { Address } from "viem";
import { EXPLORER } from "./config";
import { dur, fmt, short, RES } from "./game";
import { usePlayers, useNow } from "./data";

const PIX: Record<string, { map: string[]; pal: Record<string, string> }> = {
  wood: { map: ["..oooo..", ".obbbbo.", "obcbbcbo", "obbccbbo", "obcbbcbo", "obbbbbbo", ".obbbbo.", "..oooo.."], pal: { o: "#4a2c14", b: "#9a6332", c: "#c88d4f" } },
  food: { map: ["...y....", "..yyy...", "...yy.y.", ".y.yyyy.", ".yyyy...", "...gg...", "...g....", "..gg...."], pal: { y: "#d9a520", g: "#5f8a2e" } },
  stone: { map: ["........", "..oooo..", ".oggggo.", "oglggggo", "ogggglgo", "oggggggo", ".oooooo.", "........"], pal: { o: "#4b4a48", g: "#8d8a84", l: "#b9b5ad" } },
  iron: { map: ["........", "........", "..oooo..", ".osllso.", "osssslso", "oooooooo", "........", "........"], pal: { o: "#2f3a44", s: "#6f8494", l: "#b6c6d1" } },
  seed: { map: ["...oo...", "..oyyo..", ".oyyyyo.", ".oyhyyo.", ".oyyyyo.", "..oyyo..", "...oo...", "........"], pal: { o: "#5a3a1e", y: "#e2b04a", h: "#f6e1a0" } },
  shield: { map: [".oooooo.", "obbbbbbo", "obwwbbbo", "obwbbbbo", "obbbbbbo", ".obbbbo.", "..obbo..", "...oo..."], pal: { o: "#2e1c0e", b: "#3f6b9a", w: "#cfe0ef" } },
  sword: { map: ["......oo", ".....olo", "....olo.", "o..olo..", ".oolo...", "..oo....", ".obo....", "ob......"], pal: { o: "#2e1c0e", l: "#c9d3da", b: "#8a5a2b" } },
};
export const ICON_KEYS = ["wood", "food", "stone", "iron"];

/** Pixel icon drawn from an 8x8 map with crisp edges; decorative unless given a label. */
export function Pix({ name, size = 20, label }: { name: string; size?: number; label?: string }) {
  const p = PIX[name];
  return (
    <svg className="pix" width={size} height={size} viewBox="0 0 8 8" shapeRendering="crispEdges" role={label ? "img" : undefined} aria-label={label} aria-hidden={label ? undefined : true}>
      {p.map.flatMap((row, y) => [...row].map((ch, x) => (p.pal[ch] ? <rect key={`${x}-${y}`} x={x} y={y} width="1" height="1" fill={p.pal[ch]} /> : null)))}
    </svg>
  );
}

export function Panel({ title, children, actions, id }: { title: string; children: ReactNode; actions?: ReactNode; id?: string }) {
  return (
    <section className="panel" id={id} aria-label={title}>
      <div className="panel-head"><h2>{title}</h2>{actions}</div>
      {children}
    </section>
  );
}

/** Players always appear as name + short address. */
export function Who({ addr }: { addr?: string }) {
  const players = usePlayers();
  if (!addr || /^0x0{40}$/i.test(addr)) return <span>Wild camp</span>;
  const p = players.data?.byAddr.get(addr.toLowerCase());
  return (
    <span className="who"><strong>{p?.name ?? "Unknown"}</strong> <a className="addr" href={`${EXPLORER}/address/${addr}`} target="_blank" rel="noreferrer">{short(addr)}</a></span>
  );
}

export function Countdown({ to, done = "Ready" }: { to: number; done?: string }) {
  const now = useNow();
  const left = to - now;
  return <span className="num">{left <= 0 ? done : dur(left)}</span>;
}

export function Cost({ cost, seed }: { cost?: readonly bigint[]; seed?: bigint }) {
  if (!cost) return null;
  return (
    <span className="cost">
      {cost.map((c, i) => (c > 0n ? <span key={i} className="cost-item"><Pix name={["wood", "food", "stone", "iron"][i]} size={14} label={RES[i]} />{fmt(c)}</span> : null))}
      {seed && seed > 0n ? <span className="cost-item"><Pix name="seed" size={14} label="SEED" />{fmt(seed)}</span> : null}
    </span>
  );
}

export const Addr = ({ a }: { a: Address }) => <a className="addr" href={`${EXPLORER}/address/${a}`} target="_blank" rel="noreferrer">{short(a)}</a>;

export function Need({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}
