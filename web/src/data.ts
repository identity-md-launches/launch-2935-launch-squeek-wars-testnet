import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { BaseError, ContractFunctionRevertedError, type Address } from "viem";
import { ADDR, GAME } from "./config";
import { events, read, tryRead, type Ev } from "./chain";

export const useNow = (ms = 1000) => {
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => { const t = setInterval(() => setNow(Date.now() / 1000), ms); return () => clearInterval(t); }, [ms]);
  return now;
};

/** Squeektoshi / season state shared by every page. */
export function useGlobal() {
  return useQuery({
    queryKey: ["global"],
    refetchInterval: 30_000,
    queryFn: async () => {
      const [day, count, lastWork, week, villageCount, season, block] = await Promise.all([
        read<bigint>("ledger", "currentDay"), read<bigint>("ledger", "observationCount"), read<bigint>("ledger", "lastWork"),
        read<bigint>("clans", "week"), read<bigint>("villages", "villageCount"), read<bigint>("villages", "seasonStartedAt"),
        read<bigint>("ledger", "lastCumulativeWork"),
      ]);
      const last = count > 0n ? await read<any[]>("ledger", "observation", [count - 1n]) : null;
      const core = await tryRead<any[]>("core", "state");
      return {
        day, count, lastWork, week, villageCount, season, lastCumulative: block,
        lastObsDay: last ? (last[1] as bigint) : null,
        lastObsWork: last ? (last[2] as bigint) : 0n,
        coreWork: core ? (core[1] as bigint) : null, // cumulativeWork is the second word
      };
    },
  });
}

export type Player = { addr: Address; name: string; tile: number };
/** All villages from Founded events, the source for names, the map and rankings. */
export function usePlayers() {
  return useQuery({
    queryKey: ["players"],
    refetchInterval: 45_000,
    queryFn: async () => {
      const ev = await events("villages", "Founded");
      const list: Player[] = ev.map((e) => ({ addr: e.args.player as Address, name: e.args.name as string, tile: Number(e.args.tile) }));
      const byAddr = new Map(list.map((p) => [p.addr.toLowerCase(), p]));
      const byTile = new Map(list.map((p) => [p.tile, p]));
      return { list, byAddr, byTile };
    },
  });
}

export function useArmyEvents() {
  return useQuery({
    queryKey: ["armyEvents"],
    refetchInterval: 30_000,
    queryFn: async () => {
      const [sent, resolved, battles, scouted] = await Promise.all([
        events("army", "MovementSent", { game: GAME }), events("army", "MovementResolved", { game: GAME }),
        events("army", "Battle", { game: GAME }), events("army", "Scouted", { game: GAME }),
      ]);
      return { sent, resolved, battles, scouted };
    },
  });
}

export function useClanEvents() {
  return useQuery({ queryKey: ["clanEvents"], refetchInterval: 45_000, queryFn: () => events("clans", "ClanFounded", { game: GAME }) as Promise<Ev[]> });
}

export type Village = Awaited<ReturnType<typeof loadVillage>>;
async function loadVillage(who: Address) {
  const v = await read<any[]>("villages", "village", [who]);
  const [stock, cap, vault, room, seed, b0, b1, study, walls, home, used, training, champ, champLevel, clanId, acct, nft] = await Promise.all([
    read<bigint[]>("villages", "stock", [who]), read<bigint>("villages", "storageCapacity", [who]), read<bigint>("villages", "vaultProtection", [who]),
    read<bigint>("villages", "roomCapacity", [who]), read<bigint>("villages", "seedBalance", [who]),
    read<any[]>("villages", "buildOrder", [who, 0]), read<any[]>("villages", "buildOrder", [who, 1]), read<any[]>("villages", "study", [who]),
    read<number>("villages", "effectiveWalls", [who]), read<number[]>("army", "home", [GAME, who]), read<bigint>("army", "allocatedRoom", [GAME, who]),
    read<any[]>("army", "training", [GAME, who]), read<any[]>("army", "champion", [GAME, who]), read<bigint>("army", "championLevel", [GAME, who]),
    read<bigint>("clans", "clanOf", [GAME, who]), read<any[]>("ledger", "account", [GAME, who]), tryRead<bigint>("erc721", "balanceOf", [who], ADDR.squeek),
  ]);
  return {
    who, name: v[0] as string, tile: Number(v[1]), foundedAt: Number(v[2]), lastAccrued: Number(v[3]), shieldUntil: Number(v[4]), peaceUsedAt: Number(v[5]),
    boostUntil: Number(v[6]), repairAt: Number(v[7]), boostResource: Number(v[8]), tier: Number(v[9]), damagedWalls: Number(v[10]), banner: v[11] as boolean,
    fields: (v[12] as number[]).map(Number), buildings: (v[13] as number[]).map(Number),
    stock, cap, vault, room, seed, walls: Number(walls), home: home.map(Number), used,
    builds: [b0, b1].map((b) => ({ target: Number(b[0]), level: Number(b[1]), readyAt: Number(b[2]), cost: b[3] as bigint[], seed: b[4] as bigint })),
    study: { tier: Number(study[0]), readyAt: Number(study[1]) },
    training: { kind: Number(training[0]), count: Number(training[1]), readyAt: Number(training[2]) },
    champion: { xp: champ[0] as bigint, might: Number(champ[1]), attack: Number(champ[2]), defense: Number(champ[3]), carry: Number(champ[4]), away: champ[5] as boolean, level: Number(champLevel) },
    clanId, account: { exists: acct[0] as boolean, cursor: acct[1] as bigint, balance: acct[2] as bigint },
    nft, readAt: Date.now() / 1000,
  };
}

export function useVillage(who?: Address, enabled = true) {
  return useQuery({
    queryKey: ["village", who], enabled: !!who && enabled, refetchInterval: 20_000,
    queryFn: async () => {
      let v: any[];
      try { v = await read<any[]>("villages", "village", [who]); }
      catch (e) {
        // village() reverts NoVillage for a wallet that has not founded; network failures still throw
        if (e instanceof BaseError && e.walk((x) => x instanceof ContractFunctionRevertedError)) return null;
        throw e;
      }
      if (Number(v[2]) === 0) return null; // foundedAt == 0: no village
      return loadVillage(who!);
    },
  });
}

/** Hourly production parts from on-chain field rates, Wheelhouse bonus and upkeep. The result does
 *  not depend on the clock: whether the treasury boost is running is decided by the caller at each
 *  tick (ratePerHour / grownSince), so the label and the interpolation drop the boost exactly at
 *  boostUntil without waiting for a refetch. */
export type Rate = { base: number; wheel: number; gross: number; upkeep: number; boostable: boolean };
export function useRates(v: Village | null | undefined, lastWork: bigint | undefined) {
  return useQuery({
    queryKey: ["rates", v?.who, v?.fields.join(","), v?.buildings[2], String(lastWork), v?.boostUntil, v?.boostResource, String(v?.used)],
    enabled: !!v && lastWork !== undefined,
    queryFn: async (): Promise<Rate[]> => {
      const rates = await Promise.all(v!.fields.map((l) => read<bigint>("rules", "fieldRate", [l])));
      const wheel = Math.min(Number(lastWork!) / 4320, 0.25 * v!.buildings[2]);
      return [0, 1, 2, 3].map((i) => {
        const base = Number(rates[i * 2] + rates[i * 2 + 1]) / 1e6; // units per hour
        return { base, wheel, gross: base * (1 + wheel), upkeep: i === 1 ? Number(v!.used) * 0.5 : 0, boostable: v!.boostUntil > 0 && v!.boostResource === i };
      });
    },
  });
}

/** Net hourly rate at time t: the +25% boost counts only while t < boostUntil. */
export const ratePerHour = (r: Rate, boostUntil: number, t: number) =>
  r.gross * (r.boostable && t < boostUntil ? 1.25 : 1) - r.upkeep;

/** Units produced between two times, integrating only the boosted part of the interval. */
export function grownSince(r: Rate, boostUntil: number, from: number, to: number) {
  const span = Math.max(0, to - from);
  const boosted = r.boostable ? Math.max(0, Math.min(to, boostUntil) - from) : 0;
  return (r.gross * span + r.gross * 0.25 * boosted - r.upkeep * span) / 3600;
}
