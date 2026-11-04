export const UNIT = 1_000_000n;
export const RES = ["Wood", "Food", "Stone", "Iron"] as const;
export const FIELDS = ["Forest", "Forest", "Farm", "Farm", "Quarry", "Quarry", "Mine", "Mine"] as const;
export const BUILDINGS = ["Town Hall", "Walls", "Wheelhouse", "Storehouse", "Vault", "Burrow", "Barracks", "Academy", "Forge", "Clan Hall", "Market"] as const;
export const BUILDING_NOTE = [
  "Unlocks levels and plots; speeds building 3% per level",
  "+4% defense per level",
  "Turns hamster work into field output",
  "Raises storage for every resource",
  "Protects stock from raids",
  "Room for troops",
  "Each level above 1 multiplies training time by 0.9",
  "Hosts research tiers",
  "+2% troop attack and defense per level",
  "Join at 1, found a clan at 3",
  "Better exchange rate per level",
];
export const UNITS = ["Spearman", "Forager", "Shieldbearer", "Berserker", "Charger", "Catapult", "Scout"] as const;
export const UNIT_TIER = [0, 1, 2, 2, 3, 4, 2];
export const UNIT_SPEED = [6, 8, 5, 6, 14, 3, 16];
export const RESEARCH = [
  "Forager, Vault",
  "Shieldbearer, Berserker, Scout, Forge, Clan Hall",
  "Charger, Logistics (+20% carry)",
  "Catapult, Field Medicine (10% of losses return)",
  "Logistics II (+20% carry), Forced March (+20% speed)",
];
export const MODES: Record<number, string> = { 1: "Raid", 2: "Scouting", 3: "Support", 4: "Returning", 5: "Stationed support", 6: "Completed" };

export const fmt = (v: bigint | number, digits = 0) => {
  const n = typeof v === "bigint" ? Number(v) / 1e6 : v;
  return n.toLocaleString("en-US", { maximumFractionDigits: digits, minimumFractionDigits: 0 });
};
export const fmtInt = (v: bigint | number) => Number(v).toLocaleString("en-US");
export const short = (a?: string) => (a ? `${a.slice(0, 6)}...${a.slice(-4)}` : "");

export function dur(sec: number | bigint): string {
  let s = Math.max(0, Math.ceil(Number(sec)));
  const d = Math.floor(s / 86400); s -= d * 86400;
  const h = Math.floor(s / 3600); s -= h * 3600;
  const m = Math.floor(s / 60); s -= m * 60;
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${String(m).padStart(2, "0")}m`;
  return `${m}m ${String(s).padStart(2, "0")}s`;
}

export const campTile = (id: number) => (7919 * (50 * id + 49) + 1237) % 10000;
export const tileXY = (t: number) => ({ x: t % 100, y: Math.floor(t / 100) });
export const campSize = (id: number) => [0.6, 1, 1.5][id % 3];

/** Game day = floor((t - 4h) / 1d); next checkpoint window opens at the next 04:00 UTC. */
export const gameDay = (t: number) => Math.max(0, Math.floor((t - 4 * 3600) / 86400));
export const nextCheckpointAt = (t: number) => (gameDay(t) + 1) * 86400 + 4 * 3600;

export const NAME_RE = /^[A-Za-z0-9_]{3,16}$/;
export const CLAN_RE = /^[A-Za-z0-9_]{3,24}$/;

export function overall(c: { build: bigint; research: bigint; attack: bigint; defense: bigint }) {
  const build = Number(c.build / (100n * UNIT));
  const research = Number(c.research / (100n * UNIT));
  const combat = Math.min(build, Math.floor(Number(c.attack + c.defense) / 200));
  return { build, research, combat, total: build + research + combat };
}
