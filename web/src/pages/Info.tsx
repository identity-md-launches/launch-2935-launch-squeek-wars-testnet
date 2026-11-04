import { ADDR, EXPLORER } from "../config";
import { Pix } from "../ui";

export function Home({ hasVillage }: { hasVillage: boolean }) {
  return (
    <div className="home">
      <section className="hero">
        <img className="hero-art" src="./favicon.svg" width={96} height={96} alt="" />
        <div>
          <h1>Raise a hamster village</h1>
          <p className="lead">A free strategy game on Sepolia where SEED comes from the real work of Squeekchain's hamster.</p>
          <div className="hero-acts">
            <a className="btn btn-primary btn-lg" href={hasVillage ? "#/village" : "#/enter"}>{hasVillage ? "Open your village" : "Play the testnet"}</a>
            <a className="btn btn-secondary btn-lg" href="#/rules">Read the rules</a>
          </div>
        </div>
      </section>
      <section className="cards">
        <article className="card">
          <h2><Pix name="seed" size={24} /> SEED from real work</h2>
          <p>Squeekchain's hamster runs real work on its wheel. Once a day, anyone records that work on chain. Every village then claims work ÷ 10 SEED, and the same number speeds up fields through the Wheelhouse.</p>
        </article>
        <article className="card">
          <h2><Pix name="shield" size={24} /> How a day works</h2>
          <p>A game day starts at 04:00 UTC. The first player to press Checkpoint records the day's work for everyone. Then each player presses Claim SEED. Raid limits also reset at 04:00 UTC.</p>
        </article>
        <article className="card">
          <h2><Pix name="sword" size={24} /> Build, train, raid</h2>
          <p>Grow eight fields and eleven buildings, research five tiers, train seven troop types, raid 200 wild camps and rival villages, and climb the season and weekly rankings with your clan.</p>
        </article>
      </section>
    </div>
  );
}

export function Rules() {
  return (
    <article className="doc">
      <h1>Rules</h1>
      <p>Squeek Wars Testnet is one season on Sepolia. Every rule below is enforced by the contracts; nobody can pause, reset or change them. Resources and SEED are game points with six decimals, not tokens.</p>
      <h2>Founding</h2>
      <p>Each wallet founds one village with a name of 3 to 16 letters, digits or underscores. Names are unique ignoring case. You start with 750 of each resource, 1,500 SEED, Town Hall 1, Walls 1, eight level-1 fields and a seven-day shield. Your tile on the 100×100 map is assigned in founding order.</p>
      <h2>Days, checkpoints and SEED</h2>
      <p>A game day runs from 04:00 UTC to 04:00 UTC. Anyone may record one checkpoint per day; it reads Squeekchain's cumulative work and stores the difference since the last one. Each checkpoint adds work ÷ 10 SEED for every village, claimed with Claim SEED. Missed days are not multiplied: the next checkpoint simply carries the combined work. Each checkpoint also gives up to 150 champion XP (work ÷ 100).</p>
      <h2>Fields and production</h2>
      <p>Two Forests, Farms, Quarries and Mines produce Wood, Food, Stone and Iron. A field at level L makes 18 × 1.4^(L−1) per hour. All output gets 1 + min(work ÷ 4,320, 0.25 × Wheelhouse level). Every unit of troop room costs 0.5 Food per hour; Food stops at zero and troops never starve. Stock above storage is lost.</p>
      <h2>Buildings</h2>
      <p>Town Hall, Walls, Wheelhouse, Storehouse, Vault, Burrow, Barracks, Academy, Forge, Clan Hall and Market. Fields and buildings cannot pass your Town Hall level (Storehouse and Vault go to twice it, up to 20). You have min(12, 3 + Town Hall) plots. Two build slots run at once. Costs are paid when you order; cancel before it is ready for an 80% refund.</p>
      <p>Build time is cut 3% per Town Hall level above 1, and by up to 30% for holding Squeeks: 30% × (1 − 0.5^n) × min(1, work ÷ 11,000), sampled when you order.</p>
      <h2>Research</h2>
      <p>Five tiers, one at a time, needing Academy 1, 2, 4, 6 and 8. Tier 1 unlocks Forager and Vault; tier 2 Shieldbearer, Berserker, Scout, Forge and Clan Hall; tier 3 Charger and Logistics; tier 4 Catapult and Field Medicine; tier 5 Logistics II and Forced March.</p>
      <h2>Troops and battle</h2>
      <p>Training reserves Burrow room immediately. Each Barracks level above 1 multiplies training time by 0.9. Attack is the sum of troop attack, raised 2% per Forge level and by your champion. Defense adds home troops, clan support, the home champion, 4% per Walls level and 40 per Town Hall level. Each side loses min(1, 0.5 × enemy ÷ own) of its army. An attack at least twice the defense is decisive: it wipes the garrison, loots and damages Walls. Loot is split over four resources and only taken above the target's Vault protection. You may raid the same target three times per game day.</p>
      <h2>Scouting, support and camps</h2>
      <p>Scouts travel alone. If at least one survives, your raids on that target get a scouting bonus for 12 hours. Support goes only to clanmates and defends their village. The 200 wild camps grow stronger and richer each day and regrow 24 hours after the first damaging raid.</p>
      <h2>Market and treasury</h2>
      <p>The Market burns 100 of a resource or SEED for 25 + 5 × (Market − 1) of another resource. The treasury sells a 24-hour +25% output boost (500 SEED), a 12-hour peace shield once every three days (4,000 SEED) and a cosmetic banner (1,000 SEED).</p>
      <h2>Champion</h2>
      <p>Champion level is min(30, 1 + floor(√(XP ÷ 100))). Each level gained after level 1 grants four permanent points. Attack, defense and carry cap at 20 points each; Might can use the remaining points. Points never move once placed. Holding a Squeek multiplies XP and champion stats by 1.1.</p>
      <h2>Ranking</h2>
      <p>Overall = build + research + min(build, (attack + defense) ÷ 200), where build and research are completed spending ÷ 100 and attack and defense are the resource value of troops you destroyed. Loot counts resources taken. Season counters never reset; weekly counters use seven-day windows from launch.</p>
    </article>
  );
}

const QA: [string, string][] = [
  ["Does it cost anything?", "Only Sepolia test ETH for gas. Get some from a Sepolia faucet. Nothing in the game is a token and nothing can be sold."],
  ["Where does SEED come from?", "From Squeekchain's hamster. Each daily checkpoint reads the hamster's cumulative work and gives every village work ÷ 10 SEED to claim."],
  ["What if nobody checkpoints for a day?", "The next checkpoint carries all the work since the previous one. It is not multiplied by the missed days, so press Checkpoint daily."],
  ["Why is my build not finished at zero?", "Completion is a transaction anyone may send. Press Finish when the countdown reaches zero."],
  ["Who can resolve a movement?", "Anyone, once it has arrived. Battles use the state at resolution, not at arrival."],
  ["What do Squeeks do here?", "Holding Squeeks cuts build time by up to 30% and gives your champion 10% more XP and stats. The village itself needs no Squeek."],
  ["Can I rename or move my village?", "No. One wallet, one village, one name for the season."],
  ["How do I join a clan?", "Build a Clan Hall, ask a founder to invite your wallet, then press Join on that clan."],
  ["When does Mainnet open?", "After the official Squeek mint."],
];
export function Faq() {
  return (
    <article className="doc">
      <h1>FAQ</h1>
      {QA.map(([q, a]) => <details key={q}><summary>{q}</summary><p>{a}</p></details>)}
    </article>
  );
}

const LIST: [string, string, string][] = [
  ["Villages", ADDR.villages, "Canonical game: every player action"],
  ["Army", ADDR.army, "Troops, movements, battles, champion"],
  ["Clans", ADDR.clans, "Clans and ranking counters"],
  ["SeedLedger", ADDR.ledger, "Checkpoints and SEED"],
  ["GameRules", ADDR.rules, "Costs, times and rates"],
  ["SqueekCore", ADDR.core, "Squeekchain work counter (read only)"],
  ["Squeek NFT", ADDR.squeek, "Squeek ERC-721 balance (read only)"],
];
export function Contracts() {
  return (
    <article className="doc">
      <h1>Contracts</h1>
      <p>Sepolia (chain 11155111). The game contracts were deployed in block 12,060,202.</p>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Contract</th><th>Address</th><th>Role</th></tr></thead>
          <tbody>{LIST.map(([n, a, r]) => <tr key={n}><td>{n}</td><td><a className="mono" href={`${EXPLORER}/address/${a}`} target="_blank" rel="noreferrer">{a}</a></td><td>{r}</td></tr>)}</tbody>
        </table>
      </div>
    </article>
  );
}
