import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { isAddress, type Address } from "viem";
import { read } from "../chain";
import { GAME } from "../config";
import { useArmyEvents, useClanEvents, usePlayers, useVillage } from "../data";
import { CLAN_RE, UNITS } from "../game";
import { Act } from "../tx";
import { Need, Panel, Who } from "../ui";

export function ClanPage({ me }: { me: Address }) {
  const v = useVillage(me).data!;
  const hall = v.buildings[9];
  const clans = useClanEvents();
  const players = usePlayers();
  const army = useArmyEvents();
  const [name, setName] = useState("");
  const [invitee, setInvitee] = useState("");
  const ids = (clans.data ?? []).map((e) => e.args.clanId as bigint);
  const list = useQuery({
    queryKey: ["clans", ids.join(), String(v.clanId)],
    enabled: !!clans.data,
    queryFn: () => Promise.all(ids.map(async (id) => {
      const [c, inv] = await Promise.all([read<any[]>("clans", "clan", [GAME, id]), read<boolean>("clans", "invited", [GAME, id, me])]);
      return { id, name: c[0] as string, founder: c[1] as string, capacity: Number(c[2]), members: c[3] as string[], invited: inv };
    })),
  });
  const mine = list.data?.find((c) => c.id === v.clanId && v.clanId > 0n);
  const founder = mine && mine.founder.toLowerCase() === me.toLowerCase();
  const received = useQuery({
    queryKey: ["supportIn", me], refetchInterval: 30_000,
    queryFn: async () => {
      const ids = await read<bigint[]>("army", "supportMovements", [GAME, me]);
      return Promise.all(ids.map(async (id) => { const m = await read<any[]>("army", "movement", [GAME, id]); return { id, owner: m[0] as string, units: (m[7] as number[]).map(Number) }; }));
    },
  });
  const sentIds = (army.data?.sent ?? []).filter((e) => Number(e.args.mode) === 3 && String(e.args.owner).toLowerCase() === me.toLowerCase()).map((e) => e.args.id as bigint);
  const sent = useQuery({
    queryKey: ["supportOut", sentIds.join()], enabled: !!army.data, refetchInterval: 30_000,
    queryFn: () => Promise.all(sentIds.map(async (id) => { const m = await read<any[]>("army", "movement", [GAME, id]); return { id, target: m[1] as string, mode: Number(m[3]), units: (m[7] as number[]).map(Number) }; })),
  });
  const troops = (u: number[]) => u.map((n, i) => (n ? `${n} ${UNITS[i]}` : null)).filter(Boolean).join(", ");
  const inviteeAddr = isAddress(invitee) ? invitee : players.data?.list.find((p) => p.name.toLowerCase() === invitee.toLowerCase())?.addr;

  return (
    <div className="pagegrid">
      <Panel title={mine ? `Clan ${mine.name}` : "Your clan"}>
        <p className="muted">Clan Hall level {hall}. Level 1 lets you join with an invitation; level 3 lets you found a clan.</p>
        {mine ? (
          <>
            <p>Members {mine.members.length} of {mine.capacity}. Founder <Who addr={mine.founder} /></p>
            <ul className="members">{mine.members.map((m) => <li key={m}><Who addr={m} /></li>)}</ul>
            {founder && (
              <form className="train" onSubmit={(e) => e.preventDefault()}>
                <label htmlFor="inv">Invite by village name or address</label>
                <input id="inv" value={invitee} onChange={(e) => setInvitee(e.target.value.trim())} placeholder="Nutmeg_Hollow or 0x..." autoComplete="off" spellCheck={false} />
                {invitee && !inviteeAddr && <p className="hint bad">No village with that name or address.</p>}
                <div className="row-acts">
                  <Act label="Send invitation" c="villages" fn="inviteToClan" args={[inviteeAddr, true]} disabled={!inviteeAddr} />
                  <Act kind="secondary" label="Withdraw invitation" c="villages" fn="inviteToClan" args={[inviteeAddr, false]} disabled={!inviteeAddr} />
                  <Act kind="secondary" label="Raise capacity" c="villages" fn="raiseClanCapacity" disabled={mine.capacity >= Math.min(30, 3 * hall)} />
                </div>
              </form>
            )}
            <Act kind="danger" label="Leave clan" c="villages" fn="leaveClan" />
          </>
        ) : (
          <form className="train" onSubmit={(e) => e.preventDefault()}>
            <label htmlFor="cname">New clan name</label>
            <input id="cname" value={name} onChange={(e) => setName(e.target.value.trim())} maxLength={24} placeholder="Wheel_Runners" autoComplete="off" spellCheck={false} aria-describedby="cname-hint" />
            <p id="cname-hint" className={`hint${name && !CLAN_RE.test(name) ? " bad" : ""}`}>3 to 24 letters, digits or underscore.{hall < 3 ? " Needs Clan Hall 3." : ""}</p>
            <Act label="Found clan" c="villages" fn="foundClan" args={[name]} disabled={!CLAN_RE.test(name) || hall < 3} />
          </form>
        )}
      </Panel>
      <Panel title="Clans">
        {clans.isLoading ? <p className="muted">Reading clans...</p> : !list.data?.length ? <Need>No clans yet. Build Clan Hall 3 to found the first.</Need> : (
          <ul className="moves">
            {list.data.map((c) => (
              <li key={String(c.id)} className="slot">
                <div><strong>{c.name}</strong> <span className="muted">{c.members.length} of {c.capacity}</span><br /><span className="small">Founder <Who addr={c.founder} /></span></div>
                {!mine && c.members.length > 0 && (c.invited ? <Act small label={`Join ${c.name}`} c="villages" fn="joinClan" args={[c.id]} disabled={hall < 1} /> : <span className="muted small">Invitation needed</span>)}
              </li>
            ))}
          </ul>
        )}
      </Panel>
      <Panel title="Support">
        <h3>Received</h3>
        {received.data?.length ? <ul className="reports">{received.data.map((m) => <li key={String(m.id)}><Who addr={m.owner} />: {troops(m.units)} <Act small kind="secondary" label={`Send home #${String(m.id)}`} c="villages" fn="recall" args={[m.id]} /></li>)}</ul> : <p className="muted">No support stationed here.</p>}
        <h3>Sent</h3>
        {sent.data?.filter((m) => m.mode === 3 || m.mode === 5).length ? <ul className="reports">{sent.data.filter((m) => m.mode === 3 || m.mode === 5).map((m) => <li key={String(m.id)}>To <Who addr={m.target} />: {troops(m.units)} ({m.mode === 3 ? "on the way" : "stationed"})</li>)}</ul> : <p className="muted">No support out. Send it from the map to a clanmate.</p>}
      </Panel>
    </div>
  );
}
