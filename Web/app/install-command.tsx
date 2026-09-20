"use client";

import { useState } from "react";

export function InstallCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard access can be denied; the command stays selectable either way.
    }
  }

  return (
    <div className="flex items-center gap-3 rounded-2xl border border-line bg-surface-2 py-3.5 pr-3.5 pl-5 text-left">
      <code className="flex-1 overflow-x-auto font-mono text-[13px] whitespace-nowrap text-body sm:text-sm">
        <span className="text-muted select-none">$ </span>
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Copied" : "Copy install command"}
        className="shrink-0 rounded-full border border-line px-3 py-1.5 text-xs font-medium text-muted transition-colors hover:border-muted/40 hover:text-body"
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
