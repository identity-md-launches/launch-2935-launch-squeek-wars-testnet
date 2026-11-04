import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { read } from "../chain";
import { GAME } from "../config";
import { usePlayers, useVillage } from "../data";
import { RES, UNITS, UNIT_SPEED, campSize, campTile, dur, fmt, fmtInt, tileXY } from "../game";
import { Act } from "../tx";
import { Panel, Who } from "../ui";

const ZERO = "0x0000000000000000000000000000000000000000";
const CAMP_BY_TILE = new Map(Array.from({ length: 200 }, (_, id) => [campTile(id), id]));

function TileInfo({ me, tile }: { me: Address; tile: number }) {
  const players = usePlayers();
  const mine = useVillage(me).data!;
  const owner = players.data?.byTile.get(tile);
  const campId = CAMP_BY_TILE.get(tile);
  const [units, setUnits] = useState<number[]>([0, 0, 0, 0, 0, 0, 0]);
  const [champ, setChamp] = useState(false);
  const info = useQuery({
    queryKey: ["tile", tile, owner?.addr, campId],
    refetchInterval: 30_000,
    queryFn: async () => {
      if (owner) {
        const [home, walls, stock, same, v] = await Promise.all([
          read<number[]>("army", "home", [GAME, owner.addr]), read<number>("villages", "effectiveWalls", [owner.addr]),
          read<bigint[]>("villages", "stock", [owner.addr]), read<boolean>("clans", "sameClan", [GAME, me, owner.addr]), read<any[]>("villages", "village", [owner.addr]),
        ]);
        return { kind: "village" as const, home: home.map(Number), walls: Number(walls), stock, same, shield: Number(v[4]), th: Number((v[13] as number[])[0]) };
      }
      if (campId !== undefined) {
        const [c, p] = await Promise.all([read<any[]>("army", "camp", [GAME, campId]), read<any[]>("army", "campParameters", [campId])]);
        const fresh = !c[0] || (Number(c[1]) > 0 && Number(c[1]) <= Date.now() / 1000);
        return { kind: "camp" as const, defense: fresh ? (p[0] as bigint) : (c[3] as bigint), stock: c[4] as bigint[], hourly: p[1] as bigint, initialized: c[0] as boolean };
      }
      return null;
    },
  });
  const slowest = units.reduce((s, n, i) => (n > 0 ? Math.min(s, UNIT_SPEED[i]) : s), Infinity);
  const travel = useQuery({
    queryKey: ["travel", mine.tile, tile, slowest, mine.tier],
    enabled: slowest !== Infinity,
    queryFn: async () => {
      const t = Number(await read<bigint>("army", "travelTime", [mine.tile, tile, slowest]));
      return mine.tier >= 5 ? Math.ceil(t / 1.2) : t;
    },
  });
  const { x, y } = tileXY(tile);
  const isMe = owner?.addr.toLowerCase() === me.toLowerCase();
  const total = units.reduce((a, b) => a + b, 0);
  const onlyScouts = total > 0 && units.every((n, i) => (i === 6 ? true : n === 0));
  const target = owner ? owner.addr : ZERO;
  const args = (mode: number) => [target, campId ?? 0, units, champ && mode === 1, mode];
  const d = info.data;
  return (
    <Panel title={`Tile (${x}, ${y})`}>
      {!owner && campId === undefined && <p className="muted">Empty land.</p>}
      {owner && <p>Village <Who addr={owner.addr} />{isMe ? " (you)" : ""}</p>}
      {campId !== undefined && <p>Wild camp #{campId}, size {campSize(campId)}</p>}
      {info.isLoading && <p className="muted">Reading the tile...</p>}
      {d?.kind === "village" && (
        <dl className="kv">
          <dt>Troops at home</dt><dd>{d.home.some((n) => n) ? d.home.map((n, i) => (n ? `${n} ${UNITS[i]}` : null)).filter(Boolean).join(", ") : "None"}</dd>
          <dt>Walls</dt><dd>{d.walls}</dd><dt>Town Hall</dt><dd>{d.th}</dd>
          <dt>Stock</dt><dd>{d.stock.map((s, i) => `${fmt(s)} ${RES[i]}`).join(", ")}</dd>
          <dt>Shield</dt><dd>{d.shield > Date.now() / 1000 ? `${dur(d.shield - Date.now() / 1000)} left` : "None"}</dd>
          <dt>Clan</dt><dd>{d.same ? "Clanmate" : "Not in your clan"}</dd>
        </dl>
      )}
      {d?.kind === "camp" && (
        <dl className="kv">
          <dt>Defense</dt><dd>{fmtInt(d.defense)}</dd>
          <dt>Stock</dt><dd>{d.initialized ? d.stock.map((s, i) => `${fmt(s)} ${RES[i]}`).join(", ") : "Untouched (grows from day zero)"}</dd>
          <dt>Growth</dt><dd>{fmt(d.hourly)} of each per hour</dd>
        </dl>
      )}
      {!isMe && (owner || campId !== undefined) && (
        <form className="send" onSubmit={(e) => e.preventDefault()}>
          <fieldset>
            <legend>Troops to send (home: {mine.home.map((n, i) => (n ? `${n} ${UNITS[i]}` : null)).filter(Boolean).join(", ") || "none"})</legend>
            <div className="unit-inputs">
              {UNITS.map((u, i) => (
                <label key={u}><span>{u}</span>
                  <input type="number" inputMode="numeric" min={0} max={mine.home[i]} value={units[i] || ""} placeholder="0" disabled={!mine.home[i]}
                    onChange={(e) => setUnits(units.map((n, j) => (j === i ? Math.max(0, Math.min(mine.home[i], Math.floor(+e.target.value || 0))) : n)))} />
                </label>
              ))}
            </div>
            <label className="check"><input type="checkbox" checked={champ} onChange={(e) => setChamp(e.target.checked)} disabled={mine.champion.away} /> Champion joins the attack</label>
          </fieldset>
          <p className="muted">{total === 0 ? "Pick troops to see the travel time." : travel.data !== undefined ? `Travel time ${dur(travel.data)} each way.` : "Working out travel time..."}</p>
          <div className="row-acts">
            <Act label="Attack" c="villages" fn="send" args={args(1)} disabled={total === 0} />
            {owner && <Act kind="secondary" label="Scout" c="villages" fn="send" args={args(2)} disabled={!onlyScouts} />}
            {owner && d?.kind === "village" && d.same && <Act kind="secondary" label="Support" c="villages" fn="send" args={args(3)} disabled={total === 0 || units[6] === total} />}
          </div>
          {owner && <p className="muted small">Scouting takes only Scouts. Support goes only to clanmates.</p>}
        </form>
      )}
    </Panel>
  );
}

export function MapPage({ me }: { me: Address }) {
  const players = usePlayers();
  const mine = useVillage(me).data!;
  const canvas = useRef<HTMLCanvasElement>(null);
  const [zoom, setZoom] = useState(1);
  const [sel, setSel] = useState<number>(mine.tile);
  const drag = useRef<{ x: number; y: number; sx: number; sy: number; moved: boolean } | null>(null);
  const wrap = useRef<HTMLDivElement>(null);
  const camps = useMemo(() => new Set(CAMP_BY_TILE.keys()), []);
  const cell = 6 * zoom;

  useEffect(() => {
    const c = canvas.current; if (!c) return;
    const ctx = c.getContext("2d")!;
    c.width = 100 * cell; c.height = 100 * cell;
    ctx.fillStyle = "#cfe0a0"; ctx.fillRect(0, 0, c.width, c.height);
    for (let t = 0; t < 10000; t++) {
      const { x, y } = tileXY(t);
      if ((x + y) % 2 === 0) { ctx.fillStyle = "#c4d896"; ctx.fillRect(x * cell, y * cell, cell, cell); }
    }
    for (const t of camps) { const { x, y } = tileXY(t); ctx.fillStyle = "#7a5a3a"; ctx.fillRect(x * cell, y * cell, cell, cell); }
    for (const p of players.data?.list ?? []) { const { x, y } = tileXY(p.tile); ctx.fillStyle = "#b5462e"; ctx.fillRect(x * cell, y * cell, cell, cell); }
    const m = tileXY(mine.tile);
    ctx.fillStyle = "#f2c230"; ctx.fillRect(m.x * cell - cell, m.y * cell - cell, cell * 3, cell * 3);
    ctx.fillStyle = "#2e1c0e"; ctx.fillRect(m.x * cell, m.y * cell, cell, cell);
    const s = tileXY(sel);
    ctx.strokeStyle = "#1d4fa0"; ctx.lineWidth = Math.max(2, cell / 4); ctx.strokeRect(s.x * cell, s.y * cell, cell, cell);
  }, [cell, players.data, sel, mine.tile, camps]);

  const centerOn = (t: number) => {
    const w = wrap.current; if (!w) return;
    const { x, y } = tileXY(t);
    w.scrollTo({ left: x * cell - w.clientWidth / 2, top: y * cell - w.clientHeight / 2 });
  };
  useEffect(() => { centerOn(mine.tile); }, [zoom]); // eslint-disable-line

  const pick = (e: React.PointerEvent) => {
    const r = canvas.current!.getBoundingClientRect();
    const x = Math.floor((e.clientX - r.left) / cell), y = Math.floor((e.clientY - r.top) / cell);
    if (x >= 0 && x < 100 && y >= 0 && y < 100) setSel(y * 100 + x);
  };
  return (
    <div className="pagegrid map-layout">
      <Panel title="Map" actions={
        <div className="row-acts">
          <button className="btn btn-secondary btn-sm" aria-label="Zoom out" onClick={() => setZoom(Math.max(1, zoom / 2))} disabled={zoom <= 1}>−</button>
          <button className="btn btn-secondary btn-sm" aria-label="Zoom in" onClick={() => setZoom(Math.min(8, zoom * 2))} disabled={zoom >= 8}>+</button>
          <button className="btn btn-secondary btn-sm" onClick={() => { setSel(mine.tile); centerOn(mine.tile); }}>My village</button>
        </div>}>
        <div className="map-wrap" ref={wrap}
          onPointerDown={(e) => { const w = wrap.current!; drag.current = { x: e.clientX, y: e.clientY, sx: w.scrollLeft, sy: w.scrollTop, moved: false }; }}
          onPointerMove={(e) => { const d = drag.current; if (!d || e.pointerType !== "mouse") return; const dx = e.clientX - d.x, dy = e.clientY - d.y; if (Math.abs(dx) + Math.abs(dy) > 4) d.moved = true; wrap.current!.scrollLeft = d.sx - dx; wrap.current!.scrollTop = d.sy - dy; }}
          onPointerUp={(e) => { const d = drag.current; drag.current = null; if (!d?.moved) pick(e); }}>
          <canvas ref={canvas} role="img" aria-label={`Map of 100 by 100 tiles with ${players.data?.list.length ?? 0} villages and 200 wild camps`} />
        </div>
        <p className="legend muted small"><span className="sw" style={{ background: "#f2c230" }} /> You <span className="sw" style={{ background: "#b5462e" }} /> Villages <span className="sw" style={{ background: "#7a5a3a" }} /> Wild camps. Drag to pan, tap a tile.</p>
        <label className="goto">Go to tile <select value={sel} onChange={(e) => { setSel(+e.target.value); centerOn(+e.target.value); }}>
          {(players.data?.list ?? []).map((p) => <option key={p.addr} value={p.tile}>{p.name} ({p.tile % 100}, {Math.floor(p.tile / 100)})</option>)}
          {Array.from(CAMP_BY_TILE.entries()).slice(0, 200).map(([t, id]) => <option key={`c${id}`} value={t}>Camp #{id} ({t % 100}, {Math.floor(t / 100)})</option>)}
        </select></label>
      </Panel>
      <TileInfo key={sel} me={me} tile={sel} />
    </div>
  );
}
