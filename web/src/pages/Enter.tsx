import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { keccak256, toBytes } from "viem";
import { ConnectSheet, switchToSepolia } from "../wallet";
import { chain } from "../config";
import { read } from "../chain";
import { useVillage } from "../data";
import { NAME_RE } from "../game";
import { Act } from "../tx";

export function Enter() {
  const { address, isConnected, chainId } = useAccount();
  const v = useVillage(address);
  const [name, setName] = useState("");
  const [taken, setTaken] = useState<boolean | null>(null);
  const valid = NAME_RE.test(name);
  useEffect(() => { if (v.data) location.hash = "#/village"; }, [v.data]);
  useEffect(() => {
    setTaken(null);
    if (!valid) return;
    const t = setTimeout(async () => {
      try {
        const owner = await read<string>("villages", "nameOwner", [keccak256(toBytes(name.toLowerCase()))]);
        setTaken(!/^0x0{40}$/i.test(owner));
      } catch { setTaken(null); }
    }, 350);
    return () => clearTimeout(t);
  }, [name, valid]);
  const hint = !name ? "3 to 16 letters, digits or underscore." : !valid ? "Use 3 to 16 letters, digits or underscore only." : taken === null ? "Checking the name..." : taken ? "That name is taken. Try another." : "That name is free.";
  return (
    <div className="enter">
      <h1>Choose a world</h1>
      <div className="worlds">
        <section className="world">
          <h2>Testnet</h2>
          <p>Sepolia. Free to play with test ETH for gas.</p>
          {!isConnected ? <ConnectSheet /> : chainId !== chain.id ? (
            <button className="btn btn-primary" onClick={() => switchToSepolia().catch(() => {})}>Switch to Sepolia</button>
          ) : v.isLoading ? <p>Looking for your village...</p> : v.data ? <a className="btn btn-primary" href="#/village">Open {v.data.name}</a> : (
            <form className="found" onSubmit={(e) => e.preventDefault()}>
              <label htmlFor="vname">Village name</label>
              <input id="vname" value={name} onChange={(e) => setName(e.target.value.trim())} maxLength={16} autoComplete="off" spellCheck={false} placeholder="Nutmeg_Hollow" aria-describedby="vname-hint" aria-invalid={!!name && (!valid || taken === true)} />
              <p id="vname-hint" className={`hint${name && (!valid || taken) ? " bad" : ""}`}>{hint}</p>
              <Act label="Found village" c="villages" fn="found" args={[name]} disabled={!valid || taken !== false || !address} />
            </form>
          )}
        </section>
        <section className="world off" aria-disabled="true">
          <h2>Mainnet</h2>
          <p>Opens after the official Squeek mint.</p>
          <button className="btn btn-secondary" disabled>Not open yet</button>
        </section>
      </div>
    </div>
  );
}
