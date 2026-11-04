import { defineChain, type Abi } from "viem";
import { createConfig, http, fallback } from "wagmi";
import { coinbaseWallet, injected } from "wagmi/connectors";
import VillagesAbi from "./abi/Villages.json";
import ArmyAbi from "./abi/Army.json";
import ClansAbi from "./abi/Clans.json";
import SeedLedgerAbi from "./abi/SeedLedger.json";
import GameRulesAbi from "./abi/GameRules.json";

// From .imd/reads/deployment.json (Sepolia, launch 2935) and the brief's Squeekchain read addresses.
export const ADDR = {
  villages: "0x68dcfbff8b40429be1effaa63e82ea5200c87aec",
  army: "0x3cba4215e531ee3c4c3daa045d15803505d282e0",
  clans: "0xb789d7a3c8bb07ca1bd8811f10ee47f270d93fe1",
  ledger: "0x11d4a8126b7911bda323e4c6dc8b137bf01ba2b9",
  rules: "0xfbe6911fbaa2fdfd91ef91887f30b0d3ba8f9d15",
  core: "0x980b4424c007caf7a1f3670b48c8eaef7ebc3d44",
  squeek: "0xcb98349c134ab983da5bfd80527dfe2552bdb70f",
} as const;
export const GAME = ADDR.villages; // canonical namespace for every helper read and event filter
export const DEPLOY_BLOCK = 12060202n;

// From .imd/reads/network.json
export const RPCS = [
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://rpc.sepolia.ethpandaops.io",
  "https://sepolia.rpc.sentio.xyz",
];
export const EXPLORER = "https://sepolia.etherscan.io";
export const ADD_CHAIN = {
  chainId: "0xaa36a7",
  chainName: "Sepolia",
  rpcUrls: RPCS,
  nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
  blockExplorerUrls: [EXPLORER],
};

export const chain = defineChain({
  id: 11155111,
  name: "Sepolia",
  nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: RPCS } },
  blockExplorers: { default: { name: "Etherscan", url: EXPLORER } },
  testnet: true,
});

export const ABI = {
  villages: VillagesAbi as Abi,
  army: ArmyAbi as Abi,
  clans: ClansAbi as Abi,
  ledger: SeedLedgerAbi as Abi,
  rules: GameRulesAbi as Abi,
  core: [
    {
      type: "function", name: "state", stateMutability: "view", inputs: [],
      outputs: [{ type: "tuple", name: "", components: [
        { type: "uint64", name: "settledThroughRound" }, { type: "uint64", name: "cumulativeWork" },
        { type: "uint96", name: "cumulativeBlockUnits" }, { type: "uint64", name: "blockHeight" },
        { type: "uint96", name: "blockProgress" }, { type: "uint32", name: "workPerThousandBlocks" },
        { type: "uint256", name: "authorizationNonce" }, { type: "bool", name: "paused" } ] }],
    },
  ] as Abi,
  erc721: [
    { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address", name: "account" }], outputs: [{ type: "uint256", name: "" }] },
  ] as Abi,
};
export type Contract = keyof typeof ABI;

export const SITE_NAME = "Squeek Wars Testnet";

export const wagmiConfig = createConfig({
  chains: [chain],
  // EIP-6963 discovery lists every installed extension under its own name
  multiInjectedProviderDiscovery: true,
  connectors: [injected(), coinbaseWallet({ appName: SITE_NAME })],
  transports: { [chain.id]: fallback(RPCS.map((u) => http(u))) },
});
