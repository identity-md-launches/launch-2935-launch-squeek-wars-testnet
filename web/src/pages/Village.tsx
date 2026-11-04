import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { read } from "../chain";
import { grownSince, ratePerHour, useGlobal, useNow, useRates, useVillage, type Village } from "../data";
import { BUILDINGS, BUILDING_NOTE, FIELDS, RES, dur, fmt, short, tileXY } from "../game";
import { Act } from "../tx";
import { Cost, Countdown, ICON_KEYS, Panel, Pix } from "../ui";

type Quote = { target: number; level: number; cost: bigint[]; seed: bigint; seconds: number; base: number } | null;

function useQuotes(v: Village, lastWork?: bigint) {
  return useQuery({
    queryKey: ["quotes", v.who, v.fields.join(), v.buildings.join(), String(v.nft), String(lastWork)],
    enabled: lastWork !== undefined,
    queryFn: async (): Promise<Quote[]> => {
      const th = v.buildings[0];
      const nft = v.nft ?? 0n;
      return Promise.all(Array.from({ length: 19 }, async (_, t) => {
        const isField = t < 8;
        const level = (isField ? v.fields[t] : v.buildings[t - 8]) + 1;
        const kind = t - 8;
        const max = isField ? 10 : kind === 3 || kind === 4 ? 20 : 10;
        if (level > max) return null;
        let cost: bigint[], seed = 0n, base: bigint;
        if (isField) { const q = await read<any[]>("rules", "fieldQuote", [t, level]); cost = q[0]; base = q[1]; }
        else { const q = await read<any[]>("rules", "buildingQuote", [kind, level]); cost = q[0]; seed = q[1]; base = q[2]; }
        const seconds = await read<bigint>("rules", "buildDuration", [base, th, nft, lastWork!]);
        return { target: t, level, cost, seed, seconds: Number(seconds), base: Number(base) };
      }));
    },
  });
}

function blocker(v: Village, t: number, q: Quote): string | null {
  if (!q) return "Max level";
  const th = v.buildings[0];
  if (t < 8) return q.level > th ? `Needs Town Hall ${q.level}` : null;
  const k = t - 8;
  if (k !== 0 && q.level > th * (k === 3 || k === 4 ? 2 : 1)) return `Needs Town Hall ${k === 3 || k === 4 ? Math.ceil(q.level / 2) : q.level}`;
  if (k === 4 && v.tier < 1) return "Needs research tier 1";
  if ((k === 8 || k === 9) && v.tier < 2) return "Needs research tier 2";
  if (q.level === 1) {
    const used = v.buildings.filter((b) => b > 0).length + v.builds.filter((b) => b.readyAt && b.target >= 8 && b.level === 1).length;
    if (used >= Math.min(12, 3 + th)) return "No free plot";
  }
  return null;
}

export function VillagePage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const g = useGlobal();
  const rates = useRates(v, g.data?.lastWork);
  const quotes = useQuotes(v, g.data?.lastWork);
  const now = useNow();
  const elapsed = Math.max(0, now - v.readAt);
  const cap = Number(v.cap) / 1e6;
  const freeSlot = v.builds.findIndex((b) => b.readyAt === 0);
  const building = new Set(v.builds.filter((b) => b.readyAt).map((b) => b.target));
  const { x, y } = tileXY(v.tile);
  const targetName = (t: number) => (t < 8 ? `${FIELDS[t]} ${t % 2 + 1}` : BUILDINGS[t - 8]);

  const row = (t: number, level: number, note?: string) => {
    const q = quotes.data?.[t] ?? null;
    const block = quotes.data ? blocker(v, t, q) : null;
    return (
      <li key={t} className="plot">
        <div className="plot-head"><strong>{targetName(t)}</strong><span className="lvl">{level ? `Level ${level}` : "Not built"}</span></div>
        {note && <p className="muted">{note}</p>}
        {q ? <div className="plot-cost"><Cost cost={q.cost} seed={q.seed} /><span className="num muted">{dur(q.seconds)}</span></div> : quotes.isLoading ? <p className="muted">Loading cost...</p> : null}
        {building.has(t) ? <span className="tag">Building</span> : (
          <Act small kind="secondary" label={`Upgrade ${targetName(t)}`} c="villages" fn="orderBuild" args={[t, freeSlot < 0 ? 0 : freeSlot]} disabled={!!block || freeSlot < 0 || !q} />
        )}
        {block && q && <span className="muted small">{block}</span>}
      </li>
    );
  };

  return (
    <div className="pagegrid">
      <Panel title={`${v.name} ${short(v.who)} (${x}, ${y})`} actions={<span className="muted">{v.shieldUntil > now ? <>Shield <Countdown to={v.shieldUntil} /></> : "No shield"}</span>}>
        <ul className="res">
          {[0, 1, 2, 3].map((i) => {
            const r = rates.data?.[i];
            const val = Math.min(cap, Math.max(0, Number(v.stock[i]) / 1e6 + (r ? grownSince(r, v.boostUntil, v.readAt, v.readAt + elapsed) : 0)));
            const perHour = r ? ratePerHour(r, v.boostUntil, now) : 0;
            return (
              <li key={i}>
                <Pix name={ICON_KEYS[i]} size={28} />
                <div>
                  <span className="res-name">{RES[i]}</span>
                  <strong className="num">{fmt(val)}</strong>
                  <span className="muted small num">{r ? `${perHour >= 0 ? "+" : ""}${fmt(perHour, 1)}/h` : "..."} · cap {fmt(cap)}</span>
                </div>
              </li>
            );
          })}
          <li><Pix name="seed" size={28} /><div><span className="res-name">SEED</span><strong className="num">{fmt(v.seed)}</strong><span className="muted small">Spend on buildings and the treasury</span></div></li>
        </ul>
        <p className="muted small">Vault protects {fmt(v.vault)} of each resource from raids. Troop upkeep: {fmt(Number(v.used) * 0.5, 1)} Food per hour.{v.boostUntil > now ? ` ${RES[v.boostResource]} boost +25% for ${dur(v.boostUntil - now)}.` : ""}</p>
      </Panel>

      <Panel title="Build slots">
        <ul className="slots">
          {v.builds.map((b, i) => (
            <li key={i} className="slot">
              {b.readyAt ? (
                <>
                  <div><strong>{targetName(b.target)} to level {b.level}</strong><br /><Countdown to={b.readyAt} /></div>
                  <div className="row-acts">
                    <Act small label={`Finish slot ${i + 1}`} c="villages" fn="completeBuild" args={[me, i]} disabled={now < b.readyAt} />
                    {now < b.readyAt && <Act small kind="danger" label={`Cancel slot ${i + 1}`} c="villages" fn="cancelBuild" args={[i]} />}
                  </div>
                </>
              ) : <span className="muted">Slot {i + 1} is free. Pick an upgrade below.</span>}
            </li>
          ))}
        </ul>
        <p className="muted small">Cancel refunds 80% of the cost. Build times include Town Hall and Squeek speed bonuses.</p>
      </Panel>

      <Panel title="Fields">
        <ul className="plots">{v.fields.map((l, t) => row(t, l))}</ul>
      </Panel>
      <Panel title={`Buildings (${v.buildings.filter((b) => b > 0).length} of ${Math.min(12, 3 + v.buildings[0])} plots)`}>
        <ul className="plots">{v.buildings.map((l, k) => row(k + 8, l, BUILDING_NOTE[k]))}</ul>
      </Panel>
    </div>
  );
}
