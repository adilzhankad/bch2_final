"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const NAV_LINKS = [
  { href: "/",           label: "Home" },
  { href: "/swap",       label: "Swap" },
  { href: "/vault",      label: "Vault" },
  { href: "/lending",    label: "Lending" },
  { href: "/governance", label: "Governance" },
];

export function Navbar() {
  const pathname = usePathname();
  return (
    <header className="fixed top-0 left-0 right-0 z-50 border-b border-gray-800 bg-gray-950/80 backdrop-blur">
      <div className="max-w-5xl mx-auto px-4 h-16 flex items-center justify-between gap-6">
        <nav className="flex items-center gap-1">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors
                ${pathname === href
                  ? "bg-brand-500/10 text-brand-500"
                  : "text-gray-400 hover:text-white hover:bg-gray-800"
                }`}
            >
              {label}
            </Link>
          ))}
        </nav>
        <ConnectButton accountStatus="avatar" chainStatus="icon" />
      </div>
    </header>
  );
}
