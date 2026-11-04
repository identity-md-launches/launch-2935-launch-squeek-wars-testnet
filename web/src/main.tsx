import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "@fontsource/pixelify-sans/latin-500.css";
import "@fontsource/pixelify-sans/latin-700.css";
import "./styles.css";
import { wagmiConfig } from "./config";
import { TxProvider } from "./tx";
import App from "./App";

const qc = new QueryClient({ defaultOptions: { queries: { retry: 2, staleTime: 10_000 } } });
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={qc}>
        <TxProvider><App /></TxProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </StrictMode>,
);
