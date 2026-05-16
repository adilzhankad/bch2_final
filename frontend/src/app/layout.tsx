import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";
import { Navbar } from "@/components/Navbar";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "DeFi Super-App",
  description: "AMM · Lending · Vault · DAO — BCH2 Capstone",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>
          <Navbar />
          <main className="min-h-screen pt-20 pb-12 px-4 max-w-5xl mx-auto">
            {children}
          </main>
        </Providers>
      </body>
    </html>
  );
}
