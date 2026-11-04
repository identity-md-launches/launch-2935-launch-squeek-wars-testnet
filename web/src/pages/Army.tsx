import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { read } from "../chain";
import { GAME } from "../config";
import { useArmyEvents, useNow, useVillage } from "../data";
import { MODES, RES, UNITS, UNIT_TIER, dur, fmt, fmtInt } from "../game";
import { Act } from "../tx";
import { Cost, Countdown, Need, Panel, Who } from "../ui";

function Train({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const [kind, setKind] = useState(0);
  const [count, setCount] = useState(10);
  const q = useQuery({
    queryKey: ["unitQuote", kind, count, v.buildings[6], v.tier],
    enabled: count > 0 && v.buildings[6] > 0,
    queryFn: async () => { const r = await read<any[]>("rules", "unitQuote", [kind, v.buildings[6], v.tier, count]); return { cost: r[0] as bigint[], duration: Number(r[1]), rooms: Number(r[2]) }; },
    retry: false,
  });
  const free = Number(v.room) - Number(v.used);
  const locked = UNIT_TIER[kind] > v.tier;
  const t = v.training;
  const now = useNow();
  return (
    <Panel title="Train troops">
      <p className="muted">Room used {fmtInt(v.used)} of {fmtInt(v.room)}. Barracks level {v.buildings[6]}.</p>
      {t.readyAt > 0 ? (
        <div className="slot">
          <div><strong>{t.count} {UNITS[t.kind]}</strong><br /><Countdown to={t.readyAt} /></div>
          <Act small label="Finish training" c="army" fn="completeTraining" args={[GAME, me]} disabled={now < t.readyAt} />
        </div>
      ) : v.buildings[6] === 0 ? <Need>Build a Barracks to train troops.</Need> : (
        <form className="train" onSubmit={(e) => e.preventDefault()}>
          <label>Unit <select value={kind} onChange={(e) => setKind(+e.target.value)}>
            {UNITS.map((u, i) => <option key={u} value={i}>{u}{UNIT_TIER[i] > v.tier ? ` (research tier ${UNIT_TIER[i]})` : ""}</option>)}
          </select></label>
          <label>Count <input type="number" inputMode="numeric" min={1} value={count || ""} onChange={(e) => setCount(Math.max(0, Math.floor(+e.target.value || 0)))} /></label>
          <div className="plot-cost">{q.data ? <><Cost cost={q.data.cost} /><span className="num muted">{dur(q.data.duration)} · {q.data.rooms} room</span></> : null}</div>
          {locked && <p className="hint bad">Research tier {UNIT_TIER[kind]} unlocks the {UNITS[kind]}.</p>}
          {q.data && q.data.rooms > free && <p className="hint bad">Needs {q.data.rooms} room; {free} free. Upgrade the Burrow.</p>}
          <Act label={`Train ${count} ${UNITS[kind]}`} c="villages" fn="train" args={[kind, count]} disabled={!count || locked || (q.data ? q.data.rooms > free : true)} />
        </form>
      )}
    </Panel>
  );
}

export function ArmyPage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const ev = useArmyEvents();
  const now = useNow();
  const lower = me.toLowerCase();
  const mine = (ev.data?.sent ?? []).filter((e) => String(e.args.owner).toLowerCase() === lower || String(e.args.target).toLowerCase() === lower);
  const ids = mine.map((e) => e.args.id as bigint);
  const moves = useQuery({
    queryKey: ["moves", ids.join(), ev.dataUpdatedAt],
    enabled: !!ev.data,
    refetchInterval: 20_000,
    queryFn: async () => Promise.all(ids.map(async (id) => {
      const m = await read<any[]>("army", "movement", [GAME, id]);
      return { id, owner: m[0] as string, target: m[1] as string, campId: Number(m[2]), mode: Number(m[3]), champion: m[4] as boolean, arriveAt: Number(m[5]), units: (m[7] as number[]).map(Number), loot: m[8] as bigint[] };
    })),
  });
  const active = (moves.data ?? []).filter((m) => m.mode >= 1 && m.mode <= 5).sort((a, b) => a.arriveAt - b.arriveAt);
  const myIds = new Set(ids.map(String));
  const battles = (ev.data?.battles ?? []).filter((b) => myIds.has(String(b.args.id))).reverse();
  const scouted = (ev.data?.scouted ?? []).filter((s) => String(s.args.player).toLowerCase() === lower || String(s.args.target).toLowerCase() === lower).reverse();
  const loots = (ev.data?.resolved ?? []).filter((r) => myIds.has(String(r.args.id))).reverse();
  const sentById = new Map(mine.map((e) => [String(e.args.id), e]));
  // MovementResolved carries no amounts; the persisted Report (canonical Villages namespace) keeps the
  // loot taken in the battle, so it stays visible after the return leg resolves and empties the movement.
  const battleIds = battles.map((b) => b.args.id as bigint);
  const reports = useQuery({
    queryKey: ["reports", battleIds.join()],
    enabled: battleIds.length > 0,
    queryFn: async () => new Map(await Promise.all(battleIds.map(async (id) => {
      const r = await read<any[]>("army", "report", [GAME, id]);
      return [String(id), { resolvedAt: Number(r[0]), loot: r[5] as bigint[] }] as const;
    }))),
  });
  const lootLine = (id: bigint) => {
    const r = reports.data?.get(String(id));
    if (!r) return reports.error ? "Loot could not be read." : "Reading loot...";
    return `Looted ${r.loot.map((x, i) => `${fmt(x)} ${RES[i]}`).join(", ")}`;
  };
  return (
    <div className="pagegrid">
      <Panel title="Troops at home">
        <ul className="troops">{UNITS.map((u, i) => <li key={u}><span>{u}</span><strong className="num">{fmtInt(v.home[i])}</strong></li>)}</ul>
        <p className="muted small">Champion {v.champion.away ? "is away" : "is home"}. Room used {fmtInt(v.used)} of {fmtInt(v.room)}.</p>
      </Panel>
      <Train me={me} />
      <Panel title="Movements">
        {ev.isLoading ? <p className="muted">Reading movements...</p> : active.length === 0 ? <Need>No troops on the move. Pick a target on the <a href="#/map">map</a>.</Need> : (
          <ul className="moves">
            {active.map((m) => (
              <li key={String(m.id)} className="slot">
                <div>
                  <strong>{MODES[m.mode]} #{String(m.id)}</strong> <Who addr={m.owner} /> to {m.target === "0x0000000000000000000000000000000000000000" ? `camp #${m.campId}` : <Who addr={m.target} />}
                  <br /><span className="muted small">{m.units.map((n, i) => (n ? `${n} ${UNITS[i]}` : null)).filter(Boolean).join(", ")}{m.champion ? " + champion" : ""}{m.loot.some((x) => x > 0n) ? ` · carrying ${m.loot.map((x, i) => `${fmt(x)} ${RES[i]}`).join(", ")}` : ""}</span>
                  <br />{m.mode === 5 ? <span className="muted">Stationed</span> : <Countdown to={m.arriveAt} done="Arrived" />}
                </div>
                <div className="row-acts">
                  {m.mode !== 5 && <Act small label={`Resolve #${String(m.id)}`} c="army" fn="resolve" args={[GAME, m.id]} disabled={now < m.arriveAt} />}
                  {m.mode === 5 && <Act small kind="secondary" label={`Recall #${String(m.id)}`} c="villages" fn="recall" args={[m.id]} />}
                </div>
              </li>
            ))}
          </ul>
        )}
        <p className="muted small">Anyone may resolve an arrived movement. Both legs need resolving.</p>
      </Panel>
      <Panel title="Reports">
        {battles.length + scouted.length + loots.length === 0 ? <Need>No reports yet.</Need> : (
          <ul className="reports">
            {battles.map((b) => { const s = sentById.get(String(b.args.id)); return (
              <li key={`b${b.tx}${b.idx}`}><strong>Battle #{String(b.args.id)}</strong> {s && <><Who addr={s.args.owner} /> vs {String(s.args.target).startsWith("0x000000000000") ? `camp #${s.args.campId}` : <Who addr={s.args.target} />}</>}
                <br /><span className="num">Attack {fmtInt(b.args.attack)} vs defense {fmtInt(b.args.defense)} · {b.args.decisive ? "Decisive" : "Not decisive"} · lost {fmtInt(b.args.attackerLost)} / {fmtInt(b.args.defenderLost)}</span>
                <br /><span className="num">{lootLine(b.args.id as bigint)}</span></li>); })}
            {scouted.map((s) => <li key={`s${s.tx}${s.idx}`}><strong>Scouting</strong> <Who addr={s.args.player} /> on <Who addr={s.args.target} />: {s.args.success ? `succeeded, bonus until ${new Date(Number(s.args.until) * 1000).toLocaleString()}` : "failed"}</li>)}
            {loots.map((r) => <li key={`r${r.tx}${r.idx}`}><strong>Movement #{String(r.args.id)}</strong> resolved as {MODES[Number(r.args.mode)] ?? "done"}{Number(r.args.nextArrival) ? `, next arrival ${new Date(Number(r.args.nextArrival) * 1000).toLocaleTimeString()}` : ""}</li>)}
          </ul>
        )}
      </Panel>
    </div>
  );
}
