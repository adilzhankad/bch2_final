"use client";

import { useState } from "react";

type Status = "idle" | "loading" | "success" | "error";

interface TxButtonProps {
  label: string;
  loadingLabel?: string;
  onClick: () => Promise<void>;
  disabled?: boolean;
  variant?: "primary" | "secondary";
}

export function TxButton({
  label,
  loadingLabel = "Confirming...",
  onClick,
  disabled = false,
  variant = "primary",
}: TxButtonProps) {
  const [status, setStatus] = useState<Status>("idle");
  const [errorMsg, setErrorMsg] = useState("");

  const handleClick = async () => {
    setStatus("loading");
    setErrorMsg("");
    try {
      await onClick();
      setStatus("success");
      setTimeout(() => setStatus("idle"), 3000);
    } catch (e: unknown) {
      setStatus("error");
      setErrorMsg(humanizeError(e));
      setTimeout(() => setStatus("idle"), 6000);
    }
  };

  const cls = variant === "primary" ? "btn-primary" : "btn-secondary";

  return (
    <div className="space-y-2">
      <button
        className={cls}
        disabled={disabled || status === "loading"}
        onClick={handleClick}
      >
        {status === "loading" ? (
          <span className="flex items-center justify-center gap-2">
            <Spinner /> {loadingLabel}
          </span>
        ) : status === "success" ? (
          "Transaction Sent!"
        ) : (
          label
        )}
      </button>
      {status === "error" && (
        <p className="text-sm text-red-400 bg-red-950/50 rounded-lg px-3 py-2">
          {errorMsg}
        </p>
      )}
    </div>
  );
}

function Spinner() {
  return (
    <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
    </svg>
  );
}

function humanizeError(e: unknown): string {
  if (typeof e !== "object" || e === null) return String(e);
  const err = e as Record<string, unknown>;

  // User rejected
  if (
    err.code === 4001 ||
    err.code === "ACTION_REJECTED" ||
    String(err.message).toLowerCase().includes("rejected") ||
    String(err.message).toLowerCase().includes("denied")
  ) {
    return "Transaction rejected by wallet.";
  }

  // Insufficient balance
  if (String(err.message).toLowerCase().includes("insufficient")) {
    return "Insufficient balance for this transaction.";
  }

  // Revert with reason
  const details = String(err.message ?? "");
  const match = details.match(/reverted with reason string '([^']+)'/);
  if (match) return `Reverted: ${match[1]}`;

  const shortMatch = details.match(/reverted: (.+)/i);
  if (shortMatch) return `Reverted: ${shortMatch[1].slice(0, 100)}`;

  // Fallback: first 120 chars
  return details.slice(0, 120) || "Unknown error.";
}
