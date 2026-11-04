import { useEffect, useRef, useState, type ReactNode } from "react";
import { useAccount } from "wagmi";
import type { Address } from "viem";
import { ConnectSheet, switchToSepolia } from "./wallet";
import { Act, TxLog } from "./tx";
import { useGlobal, useNow, useVillage } from "./data";
import { dur, fmt, fmtInt, gameDay, nextCheckpointAt } from "./game";
import { chain } from "./config";
import { Home, Rules, Faq, Contracts } from "./pages/Info";
import { Enter } from "./pages/Enter";
import { VillagePage } from "./pages/Village";
import { MapPage } from "./pages/Map";
import { ArmyPage } from "./pages/Army";
import { AcademyPage, MarketPage, ChampionPage } from "./pages/More";
import { ClanPage } from "./pages/Clan";
import { RankingPage } from "./pages/Ranking";

export const useRoute = () => {
  const get = () => location.hash.replace(/^#\/?/, "").split("?")[0] || "";
  const [r, setR] = useState(get);
  useEffect(() => { const f = () => setR(get()); addEventListener("hashchange", f); return () => removeEventListener("hashchange", f); }, []);
  return r;
};

const GAME_NAV = [["village", "Village"], ["map", "Map"], ["army", "Army"], ["academy", "Academy"], ["market", "Market"], ["champion", "Champion"], ["clan", "Clan"], ["ranking", "Ranking"]];
const INFO_NAV = [["rules", "Rules"], ["faq", "FAQ"], ["ranking", "Ranking"], ["contracts", "Contracts"]];

/** Squeektoshi panel: always visible, game day, work, SEED per day, bonuses and the next checkpoint. */
function SqueekPanel({ me }: { me?: Address }) {
  const g = useGlobal();
  const v = useVillage(me);
  const now = useNow();
  const d = g.data;
  const work = d ? Number(d.lastWork) : 0;
  const wheelLvl = v.data?.buildings[2] ?? 0;
  const wheel = Math.min(work / 4320, 0.25 * wheelLvl);
  const n = v.data?.nft !== undefined && v.data?.nft !== null ? Number(v.data.nft) : null;
  const speed = n === null ? null : 0.3 * (1 - Math.pow(0.5, Math.min(n, 32))) * Math.min(1, work / 11000);
  const needCheckpoint = d && (d.count === 0n || d.lastObsDay !== d.day);
  const canClaim = d && v.data && v.data.account.exists && d.count > 0n && v.data.account.cursor < d.count - 1n;
  return (
    <aside className="squeek" aria-label="Squeektoshi">
      <dl className="squeek-stats">
        <div><dt>Season day</dt><dd className="num">{d ? fmtInt(Number(d.day) - gameDay(Number(d.season))) : "..."}</dd></div>
        <div><dt>Last checkpoint work</dt><dd className="num">{!d ? "..." : d.count === 0n ? "None yet" : d.count === 1n ? "Baseline set" : fmtInt(d.lastObsWork)}</dd></div>
        <div><dt>Hamster work counter</dt><dd className="num">{!d ? "..." : d.coreWork === null ? "Unavailable" : fmtInt(d.coreWork)}</dd></div>
        <div><dt>SEED / village / day</dt><dd className="num">{d ? fmt(work / 10, 1) : "..."}</dd></div>
        <div><dt>Wheelhouse bonus</dt><dd className="num">{me && v.data ? `+${(wheel * 100).toFixed(1)}%` : `up to +${((work / 4320) * 100).toFixed(1)}%`}</dd></div>
        <div><dt>Your Squeeks</dt><dd className="num">{!me ? "Found a village to see" : n === null ? "Unavailable" : `${n} · ${((speed ?? 0) * 100).toFixed(1)}% faster builds`}</dd></div>
        <div><dt>Next checkpoint</dt><dd className="num">{dur(nextCheckpointAt(now) - now)}</dd></div>
      </dl>
      <div className="squeek-acts">
        {needCheckpoint && <Act small label="Checkpoint" c="ledger" fn="checkpoint" />}
        {canClaim && <Act small label="Claim SEED" c="villages" fn="claimSeed" />}
      </div>
      {g.error && <p className="note">Sepolia RPCs are not answering. Retrying.</p>}
    </aside>
  );
}

/** Game pages: connect, switch chain and found a village first. */
function Gate({ children }: { children: (me: Address) => ReactNode }) {
  const { address, isConnected, chainId } = useAccount();
  const v = useVillage(address);
  if (!isConnected || !address) return <div className="gate"><h1>Connect to play</h1><p>Connect a wallet to open your village.</p><ConnectSheet /></div>;
  if (chainId !== chain.id) return <div className="gate"><h1>Switch to Sepolia</h1><p>Squeek Wars Testnet runs on Sepolia.</p><button className="btn btn-primary" onClick={() => switchToSepolia().catch(() => {})}>Switch to Sepolia</button></div>;
  if (v.isLoading) return <div className="gate"><p>Loading your village...</p></div>;
  if (v.error) return <div className="gate"><p>Could not read Sepolia. Retrying...</p></div>;
  if (!v.data) return <div className="gate"><h1>No village yet</h1><p>Found a village to start playing.</p><a className="btn btn-primary" href="#/enter">Found a village</a></div>;
  return <>{children(address)}</>;
}

export default function App() {
  const route = useRoute();
  const { address } = useAccount();
  const v = useVillage(address);
  const main = useRef<HTMLElement>(null);
  const inGame = GAME_NAV.some(([k]) => k === route) && route !== "ranking";
  useEffect(() => { main.current?.focus({ preventScroll: true }); scrollTo(0, 0); }, [route]);
  const nav = v.data ? GAME_NAV : INFO_NAV;
  let page: ReactNode;
  switch (route) {
    case "": page = <Home hasVillage={!!v.data} />; break;
    case "rules": page = <Rules />; break;
    case "faq": page = <Faq />; break;
    case "contracts": page = <Contracts />; break;
    case "enter": page = <Enter />; break;
    case "ranking": page = <RankingPage me={address} />; break;
    case "map": page = <Gate>{(me) => <MapPage me={me} />}</Gate>; break;
    case "village": page = <Gate>{(me) => <VillagePage me={me} />}</Gate>; break;
    case "army": page = <Gate>{(me) => <ArmyPage me={me} />}</Gate>; break;
    case "academy": page = <Gate>{(me) => <AcademyPage me={me} />}</Gate>; break;
    case "market": page = <Gate>{(me) => <MarketPage me={me} />}</Gate>; break;
    case "champion": page = <Gate>{(me) => <ChampionPage me={me} />}</Gate>; break;
    case "clan": page = <Gate>{(me) => <ClanPage me={me} />}</Gate>; break;
    default: page = <div className="gate"><h1>Page not found</h1><a className="btn btn-primary" href="#/">Go to the start page</a></div>;
  }
  return (
    <>
      <a className="skip" href="#main" onClick={(e) => { e.preventDefault(); main.current?.focus(); }}>Skip to content</a>
      <header className="top">
        <a className="brand" href="#/" aria-label="Squeek Wars home"><img src="./favicon.svg" width={32} height={32} alt="" /><span>Squeek Wars</span></a>
        <ConnectSheet compact />
      </header>
      <nav className="nav" aria-label="Main">
        {nav.map(([k, label]) => <a key={k} href={`#/${k}`} aria-current={route === k ? "page" : undefined}>{label}</a>)}
      </nav>
      <SqueekPanel me={v.data ? address : undefined} />
      <main id="main" ref={main} tabIndex={-1} className={inGame ? "game" : undefined}>{page}</main>
      <TxLog />
      <footer className="foot">
        <a href="#/rules">Rules</a><a href="#/faq">FAQ</a><a href="#/contracts">Contracts</a>
        <span>Testnet only. Resources and SEED are game points, not tokens.</span>
      </footer>
    </>
  );
}
