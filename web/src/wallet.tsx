import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, type Connector } from "wagmi";
import { getAccount } from "@wagmi/core";
import { ADD_CHAIN, chain, wagmiConfig } from "./config";
import { short } from "./game";

/** wallet_switchEthereumChain, falling back to wallet_addEthereumChain with network.json's parameters. */
export async function switchToSepolia() {
  const conn = getAccount(wagmiConfig).connector;
  const provider: any = await conn?.getProvider();
  if (!provider) throw new Error("No wallet provider found.");
  try {
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: ADD_CHAIN.chainId }] });
  } catch (e: any) {
    if (e?.code === 4902 || /unrecognized|not been added|unknown chain/i.test(String(e?.message))) {
      await provider.request({ method: "wallet_addEthereumChain", params: [ADD_CHAIN] });
    } else throw e;
  }
}

const COINBASE = `<svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="28" height="28" fill="#2C5FF6"/><path fill-rule="evenodd" clip-rule="evenodd" d="M14 23.8C19.4124 23.8 23.8 19.4124 23.8 14C23.8 8.58761 19.4124 4.2 14 4.2C8.58761 4.2 4.2 8.58761 4.2 14C4.2 19.4124 8.58761 23.8 14 23.8ZM11.55 10.8C11.1358 10.8 10.8 11.1358 10.8 11.55V16.45C10.8 16.8642 11.1358 17.2 11.55 17.2H16.45C16.8642 17.2 17.2 16.8642 17.2 16.45V11.55C17.2 11.1358 16.8642 10.8 16.45 10.8H11.55Z" fill="white"/></svg>`;
const METAMASK = `<svg width="28" height="28" viewBox="0 0 28 28" xmlns="http://www.w3.org/2000/svg"><rect width="28" height="28" fill="#fff"/><path d="M22 6l-6.6 4.9 1.2-2.9z" fill="#e2761b"/><path d="M6 6l6.5 5-1.1-3zM19.6 18.4l-1.8 2.7 3.8 1 1.1-3.6zM5.3 18.5l1.1 3.6 3.8-1-1.8-2.7z" fill="#e4761b"/><path d="M10 13.2l-1 1.6 3.8.2-.1-4.1zM18 13.2l-2.7-2.4-.1 4.2 3.8-.2zM10.2 21.1l2.3-1.1-2-1.5zM15.5 20l2.3 1.1-.3-2.6z" fill="#e4761b"/><path d="M17.8 21.1l-2.3-1.1.2 1.5v.6zM10.2 21.1l2.1 1v-.6l.2-1.5z" fill="#d7c1b3"/><path d="M12.4 17.4l-1.9-.6 1.3-.6zM15.6 17.4l.6-1.2 1.3.6z" fill="#233447"/></svg>`;
const RABBY = `<svg width="28" height="28" viewBox="0 0 28 28" xmlns="http://www.w3.org/2000/svg"><rect width="28" height="28" fill="#8697FF"/><path d="M22.5 15.2c.7-1.5-2.8-5.8-6.1-7.6-2.1-1.4-4.3-1.2-4.7-.6-1 1.4 3.2 2.5 6 3.9-.6.3-1.2.7-1.5 1.3-1-1.1-3.3-2.1-6-1.3-1.8.5-3.3 1.8-3.9 3.6-.2-.1-.5-.1-.7-.1-.6 0-1.1.5-1.1 1.1s.5 1.1 1.1 1.1h.3l3.9.1c-3.9 3.1 1.5 5.2 3 4.1-.4.6-.2 1.2.4 1.2 3.6.6 7-2 7.9-3.8 1.4-2.2 1.3-2.4 2-3z" fill="#fff"/></svg>`;
const PHANTOM = `<svg width="28" height="28" viewBox="0 0 28 28" xmlns="http://www.w3.org/2000/svg"><rect width="28" height="28" fill="#AB9FF2"/><path d="M8.2 20.6c2.1 0 3.6-1.8 4.6-3.3-.1.3-.2.7-.2 1 0 .9.5 1.5 1.5 1.5 1.4 0 2.8-1.2 3.6-2.5 0 .2-.1.4-.1.5 0 .6.4 1 1 1 2 0 4-3.5 4-6.6 0-2.4-1.2-4.5-4.3-4.5-5.4 0-11.2 6.6-11.2 10.9 0 1.7.9 2 1.1 2z" fill="#fffdf8"/><path d="M16 11.5c0-.6.3-1 .8-1s.8.4.8 1-.3 1-.8 1-.8-.4-.8-1zm2.6 0c0-.6.3-1 .8-1s.8.4.8 1-.3 1-.8 1-.8-.4-.8-1z" fill="#AB9FF2"/></svg>`;
const ICONS: Record<string, string> = { coinbaseWalletSDK: COINBASE, coinbase: COINBASE, metamask: METAMASK, rabby: RABBY, phantom: PHANTOM };
const svgUrl = (s: string) => `data:image/svg+xml;utf8,${encodeURIComponent(s)}`;

export const OPEN_IN: ReadonlyArray<{ id: string; name: string; href: (url: string) => string }> = [
  { id: "metamask", name: "MetaMask", href: (url) => `https://link.metamask.io/dapp/${url.replace(/^https?:\/\//, "")}` },
  { id: "coinbase", name: "Coinbase Wallet", href: (url) => `https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(url)}` },
  { id: "rabby", name: "Rabby", href: (url) => `https://go.rabby.io/mobile/dapp?url=${encodeURIComponent(url)}` },
  { id: "phantom", name: "Phantom", href: (url) => `https://phantom.app/ul/browse/${encodeURIComponent(url)}?ref=${encodeURIComponent(new URL(url).origin)}` },
];
export const isMobileBrowser = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) && !(window as any).ethereum;

/** One connect control: EIP-6963 wallets, Coinbase, and "Open in" links on phones. */
export function ConnectSheet({ compact }: { compact?: boolean }) {
  const mobile = isMobileBrowser();
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending, variables, error, reset } = useConnect();
  const { disconnect } = useDisconnect();
  const [open, setOpen] = useState(false);
  const [menu, setMenu] = useState(false);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [open]);
  useEffect(() => { if (isConnected) setOpen(false); }, [isConnected]);

  const named = connectors.some((c) => c.type === "injected" && c.id !== "injected");
  const listed = [...connectors.filter((c) => c.type === "injected"), ...connectors.filter((c) => c.type !== "injected")]
    .filter((c) => !(c.id === "injected" && named));
  const label = (c: Connector) => (c.id === "injected" ? "Browser wallet" : c.id === "coinbaseWalletSDK" && mobile ? "Coinbase Smart Wallet" : c.name);
  const icon = (c: Connector) => c.icon ?? (ICONS[c.id] ? svgUrl(ICONS[c.id]) : undefined);

  if (isConnected && address) {
    if (chainId !== chain.id) return <button className="btn btn-primary" onClick={() => switchToSepolia().catch(() => {})}>Switch to Sepolia</button>;
    return (
      <div className="acct">
        <button className="btn btn-secondary" aria-expanded={menu} onClick={() => setMenu(!menu)}>{short(address)}</button>
        {menu && <button className="btn btn-secondary acct-menu" onClick={() => { setMenu(false); disconnect(); }}>Disconnect</button>}
      </div>
    );
  }
  return (
    <>
      <button className={`btn btn-primary${compact ? " btn-sm" : ""}`} onClick={() => { reset(); setOpen(true); }}>Connect</button>
      {open && (
        <div className="sheet-bg" onClick={() => setOpen(false)}>
          <div className="sheet" role="dialog" aria-modal="true" aria-label="Connect a wallet" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-head"><h2>Connect a wallet</h2><button className="x" aria-label="Close" autoFocus onClick={() => setOpen(false)}>×</button></div>
            {mobile && OPEN_IN.map((w) => (
              <a key={w.id} className="row" href={w.href(location.href)}>
                <span className="ic"><img width={28} height={28} src={svgUrl(ICONS[w.id])} alt="" /></span>
                <span>Open in {w.name}</span>
              </a>
            ))}
            {listed.filter((c) => !mobile || c.type !== "injected").map((c) => (
              <button key={c.uid} className="row" onClick={() => connect({ connector: c, chainId: chain.id })} disabled={isPending}>
                <span className="ic">{icon(c) ? <img width={28} height={28} src={icon(c)} alt="" /> : null}</span>
                <span>{label(c)}{isPending && variables?.connector === c ? " · opening..." : ""}</span>
              </button>
            ))}
            {error && <p className="note">{/rejected/i.test(error.message) ? "You closed the wallet prompt. Pick a wallet to try again." : error.message.split("\n")[0]}</p>}
          </div>
        </div>
      )}
    </>
  );
}
