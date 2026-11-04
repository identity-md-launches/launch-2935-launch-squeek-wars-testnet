import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { read, tryRead } from "../chain";
import { GAME } from "../config";
import { useNow, useVillage } from "../data";
import { RES, RESEARCH, dur, fmt, fmtInt } from "../game";
import { Act } from "../tx";
import { Cost, Countdown, Need, Panel } from "../ui";

export function AcademyPage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const now = useNow();
  const q = useQuery({
    queryKey: ["research"], staleTime: Infinity,
    queryFn: () => Promise.all([1, 2, 3, 4, 5].map(async (t) => { const r = await read<any[]>("rules", "researchQuote", [t]); return { tier: t, cost: r[0] as bigint[], seed: r[1] as bigint, seconds: Number(r[2]), academy: Number(r[3]) }; })),
  });
  const s = v.study;
  return (
    <Panel title="Academy research">
      <p className="muted">Academy level {v.buildings[7]}. Tiers run one at a time, in order. Research time has no speed bonus.</p>
      <ol className="tiers">
        {(q.data ?? []).map((r) => {
          const done = v.tier >= r.tier;
          const running = s.readyAt > 0 && s.tier === r.tier;
          const next = v.tier + 1 === r.tier;
          return (
            <li key={r.tier} className={`tier${done ? " done" : ""}`}>
              <div className="plot-head"><strong>Tier {r.tier}</strong><span className="lvl">{done ? "Researched" : running ? "Studying" : `Academy ${r.academy}`}</span></div>
              <p>Unlocks {RESEARCH[r.tier - 1]}.</p>
              <div className="plot-cost"><Cost cost={r.cost} seed={r.seed} /><span className="num muted">{dur(r.seconds)}</span></div>
              {running && <div className="row-acts"><Countdown to={s.readyAt} /><Act small label="Finish research" c="villages" fn="completeResearch" args={[me]} disabled={now < s.readyAt} /></div>}
              {next && !running && s.readyAt === 0 && <Act small label={`Research tier ${r.tier}`} c="villages" fn="orderResearch" disabled={v.buildings[7] < r.academy} />}
              {next && !running && v.buildings[7] < r.academy && <span className="muted small">Needs Academy {r.academy}</span>}
            </li>
          );
        })}
      </ol>
      {q.isLoading && <p className="muted">Loading research costs...</p>}
    </Panel>
  );
}

export function MarketPage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const now = useNow();
  const [input, setInput] = useState(0);
  const [output, setOutput] = useState(1);
  const [lots, setLots] = useState(1);
  const [boostRes, setBoostRes] = useState(0);
  const market = v.buildings[10];
  const per = 25 + 5 * Math.max(0, market - 1);
  const shieldOk = v.shieldUntil < now + 12 * 3600 && (v.peaceUsedAt === 0 || now >= v.peaceUsedAt + 3 * 86400);
  return (
    <div className="pagegrid">
      <Panel title="Market">
        {market === 0 ? <Need>Build a Market in your village to trade.</Need> : (
          <form className="train" onSubmit={(e) => e.preventDefault()}>
            <p className="muted">Each lot burns 100 of the input and gives {per} of the output.</p>
            <label>Give <select value={input} onChange={(e) => setInput(+e.target.value)}>{[...RES, "SEED"].map((r, i) => <option key={r} value={i}>{r}</option>)}</select></label>
            <label>Get <select value={output} onChange={(e) => setOutput(+e.target.value)}>{RES.map((r, i) => <option key={r} value={i} disabled={i === input}>{r}</option>)}</select></label>
            <label>Lots <input type="number" inputMode="numeric" min={1} value={lots || ""} onChange={(e) => setLots(Math.max(0, Math.floor(+e.target.value || 0)))} /></label>
            <p className="num">{fmtInt(lots * 100)} {[...RES, "SEED"][input]} for {fmtInt(lots * per)} {RES[output]}</p>
            <Act label="Exchange" c="villages" fn="exchange" args={[input, output, lots]} disabled={!lots || input === output} />
          </form>
        )}
      </Panel>
      <Panel title="Treasury">
        <p>SEED balance <strong className="num">{fmt(v.seed)}</strong></p>
        <ul className="plots">
          <li className="plot">
            <div className="plot-head"><strong>Output boost</strong><span className="lvl">500 SEED</span></div>
            <p className="muted">+25% output of one resource for 24 hours.</p>
            {v.boostUntil > now ? <p>{RES[v.boostResource]} boost: <Countdown to={v.boostUntil} /></p> : (
              <div className="row-acts">
                <label className="inline">Resource <select value={boostRes} onChange={(e) => setBoostRes(+e.target.value)}>{RES.map((r, i) => <option key={r} value={i}>{r}</option>)}</select></label>
                <Act small label="Buy boost" c="villages" fn="treasury" args={[0, boostRes]} />
              </div>
            )}
          </li>
          <li className="plot">
            <div className="plot-head"><strong>Peace shield</strong><span className="lvl">4,000 SEED</span></div>
            <p className="muted">12 hours safe from raids, once every three days.</p>
            {v.shieldUntil > now && <p>Shield: <Countdown to={v.shieldUntil} /></p>}
            <Act small label="Buy peace shield" c="villages" fn="treasury" args={[1, 0]} disabled={!shieldOk} />
            {!shieldOk && <span className="muted small">{v.shieldUntil >= now + 12 * 3600 ? "A longer shield is already running." : "Cooldown: three days between shields."}</span>}
          </li>
          <li className="plot">
            <div className="plot-head"><strong>Banner</strong><span className="lvl">1,000 SEED</span></div>
            <p className="muted">A cosmetic banner for your village, once only.</p>
            {v.banner ? <span className="tag">Owned</span> : <Act small label="Buy banner" c="villages" fn="treasury" args={[2, 0]} />}
          </li>
        </ul>
      </Panel>
    </div>
  );
}

const STATS = ["Might", "Attack", "Defense", "Carry"] as const;
export function ChampionPage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const c = v.champion;
  const cur = [c.might, c.attack, c.defense, c.carry];
  const [alloc, setAlloc] = useState(cur);
  useEffect(() => setAlloc([c.might, c.attack, c.defense, c.carry]), [c.might, c.attack, c.defense, c.carry]);
  const stats = useQuery({ queryKey: ["champStats", me, cur.join()], queryFn: () => tryRead<any[]>("army", "championStats", [GAME, me]) });
  const total = 4 * (c.level - 1);
  const free = total - alloc.reduce((a, b) => a + b, 0);
  const nextXp = c.level >= 30 ? null : 100 * c.level * c.level;
  const changed = alloc.some((a, i) => a !== cur[i]);
  return (
    <Panel title="Champion">
      <dl className="kv">
        <dt>Level</dt><dd className="num">{c.level}</dd>
        <dt>XP</dt><dd className="num">{fmtInt(c.xp)}{nextXp ? ` (next level at ${fmtInt(nextXp)})` : ""}</dd>
        <dt>Free points</dt><dd className="num">{Math.max(0, total - cur.reduce((a, b) => a + b, 0))}</dd>
        <dt>Status</dt><dd>{c.away ? "Away with an attack" : "Home"}</dd>
        {stats.data && <><dt>Live stats</dt><dd className="num">Might {fmtInt(stats.data[0])}, attack +{(Number(stats.data[1]) / 1e4).toFixed(1)}%, defense +{(Number(stats.data[2]) / 1e4).toFixed(1)}%, carry +{(Number(stats.data[3]) / 1e4).toFixed(1)}%</dd></>}
        {stats.data === null && <><dt>Live stats</dt><dd>Unavailable: the Squeek NFT could not be read.</dd></>}
      </dl>
      <form className="alloc" onSubmit={(e) => e.preventDefault()}>
        {STATS.map((s, i) => (
          <div key={s} className="stat">
            <span>{s} <span className="muted small">{i === 0 ? "50 + 25 each" : i === 3 ? "+1% carry each" : "+0.5% each"}</span></span>
            <div className="stepper">
              <button type="button" className="btn btn-secondary btn-sm" aria-label={`Remove a point from ${s}`} disabled={alloc[i] <= cur[i]} onClick={() => setAlloc(alloc.map((a, j) => (j === i ? a - 1 : a)))}>−</button>
              <output className="num" aria-live="polite">{alloc[i]}</output>
              <button type="button" className="btn btn-secondary btn-sm" aria-label={`Add a point to ${s}`} disabled={free <= 0 || (i > 0 && alloc[i] >= 20)} onClick={() => setAlloc(alloc.map((a, j) => (j === i ? a + 1 : a)))}>+</button>
            </div>
          </div>
        ))}
        <p className="muted small">Points are permanent. {free} left to place.</p>
        <Act label="Save points" c="villages" fn="allocateChampion" args={alloc} disabled={!changed || free < 0} />
      </form>
    </Panel>
  );
}
