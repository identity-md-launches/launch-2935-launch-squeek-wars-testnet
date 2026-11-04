import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { read } from "../chain";
import { GAME } from "../config";
import { useGlobal, usePlayers } from "../data";
import { fmt, fmtInt, overall } from "../game";
import { Need, Panel, Who } from "../ui";

const TABS = ["Overall", "Attack", "Defense", "Loot", "Clans"] as const;
type Tab = (typeof TABS)[number];

export function RankingPage({ me }: { me?: Address }) {
  const players = usePlayers();
  const g = useGlobal();
  const [weekly, setWeekly] = useState(false);
  const [tab, setTab] = useState<Tab>("Overall");
  const week = g.data?.week ?? 0n;
  const rows = useQuery({
    queryKey: ["ranking", weekly, String(week), players.data?.list.length],
    enabled: !!players.data && !!g.data,
    refetchInterval: 60_000,
    queryFn: () => Promise.all(players.data!.list.map(async (p) => {
      const [c, clan] = await Promise.all([read<any[]>("clans", "counters", [GAME, p.addr, weekly, week]), read<bigint>("clans", "clanOf", [GAME, p.addr])]);
      const counters = { build: c[0] as bigint, research: c[1] as bigint, attack: c[2] as bigint, defense: c[3] as bigint, loot: c[4] as bigint };
      return { p, clan, counters, o: overall(counters) };
    })),
  });
  const clanIds = [...new Set((rows.data ?? []).filter((r) => r.clan > 0n).map((r) => r.clan))];
  const clanNames = useQuery({
    queryKey: ["clanNames", clanIds.join()], enabled: clanIds.length > 0,
    queryFn: async () => new Map(await Promise.all(clanIds.map(async (id) => [String(id), (await read<any[]>("clans", "clan", [GAME, id]))[0] as string] as const))),
  });
  const data = rows.data ?? [];
  const sorted = [...data].sort((a, b) => {
    const k = (r: (typeof data)[number]) => (tab === "Overall" ? r.o.total : tab === "Attack" ? Number(r.counters.attack) : tab === "Defense" ? Number(r.counters.defense) : Number(r.counters.loot));
    return k(b) - k(a);
  });
  const clanTotals = [...data.reduce((m, r) => (r.clan > 0n ? m.set(String(r.clan), (m.get(String(r.clan)) ?? 0) + r.o.total) : m), new Map<string, number>())].sort((a, b) => b[1] - a[1]);
  return (
    <Panel title="Ranking">
      <div className="tabs" role="group" aria-label="Period">
        <button className={`tab${!weekly ? " on" : ""}`} aria-pressed={!weekly} onClick={() => setWeekly(false)}>Season</button>
        <button className={`tab${weekly ? " on" : ""}`} aria-pressed={weekly} onClick={() => setWeekly(true)}>Week {String(week + 1n)}</button>
      </div>
      <div className="tabs" role="group" aria-label="Category">
        {TABS.map((t) => <button key={t} className={`tab${tab === t ? " on" : ""}`} aria-pressed={tab === t} onClick={() => setTab(t)}>{t}</button>)}
      </div>
      {rows.isLoading || players.isLoading ? <p className="muted">Reading every village's counters...</p> : rows.error ? <p className="hint bad">Could not read the rankings. Retrying.</p> : data.length === 0 ? <Need>No villages yet. <a href="#/enter">Found the first one.</a></Need> : tab === "Clans" ? (
        clanTotals.length === 0 ? <Need>No clans yet.</Need> : (
          <div className="table-wrap"><table>
            <thead><tr><th>#</th><th>Clan</th><th className="r">Overall</th></tr></thead>
            <tbody>{clanTotals.map(([id, total], i) => <tr key={id}><td>{i + 1}</td><td>{clanNames.data?.get(id) ?? `Clan ${id}`}</td><td className="r num">{fmtInt(total)}</td></tr>)}</tbody>
          </table></div>
        )
      ) : (
        <div className="table-wrap"><table>
          <thead><tr><th>#</th><th>Player</th>{tab === "Overall" ? <><th className="r">Build</th><th className="r">Research</th><th className="r">Combat</th><th className="r">Overall</th></> : <th className="r">{tab === "Loot" ? "Resources looted" : "Killed value"}</th>}</tr></thead>
          <tbody>{sorted.map((r, i) => (
            <tr key={r.p.addr} className={me && r.p.addr.toLowerCase() === me.toLowerCase() ? "me" : undefined}>
              <td>{i + 1}</td><td><Who addr={r.p.addr} /></td>
              {tab === "Overall" ? <><td className="r num">{fmtInt(r.o.build)}</td><td className="r num">{fmtInt(r.o.research)}</td><td className="r num">{fmtInt(r.o.combat)}</td><td className="r num"><strong>{fmtInt(r.o.total)}</strong></td></>
                : <td className="r num">{tab === "Loot" ? fmt(r.counters.loot) : fmtInt(tab === "Attack" ? r.counters.attack : r.counters.defense)}</td>}
            </tr>))}</tbody>
        </table></div>
      )}
      <p className="muted small">Overall = build + research + min(build, (attack + defense) ÷ 200). Combat is that last part.</p>
    </Panel>
  );
}
