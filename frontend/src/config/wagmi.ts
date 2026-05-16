import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { optimismSepolia } from "wagmi/chains";

export const wagmiConfig = getDefaultConfig({
  appName: "DeFi Super-App",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "demo",
  chains: [optimismSepolia],
  ssr: true,
});

export const TARGET_CHAIN = optimismSepolia;
