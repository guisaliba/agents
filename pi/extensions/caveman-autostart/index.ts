import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type CavemanLevel = "off" | "ultra";

let currentLevel: CavemanLevel = "ultra";

const CAVEMAN_INSTRUCTIONS =
  "CAVEMAN ULTRA MODE ACTIVE. Drop articles/filler/pleasantries/hedging/connective prose. " +
  "Bare fragments. Abbrev common prose words: DB/auth/config/req/res/fn/impl. " +
  "Use arrows for causality. Prefer compact bullets/tables. Technical terms exact. " +
  "Keep code, paths, commands, and error strings unchanged. " +
  "Pattern: [thing] [action] [reason]. [next step]. " +
  "Code/commits/PRs/security/irreversible actions: write normal precise prose. " +
  "Stop only when user says stop caveman or normal mode.";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async () => {
    currentLevel = "ultra";
  });

  pi.on("input", async (event) => {
    const text = event.text.toLowerCase();

    if (text.includes("stop caveman") || text.includes("normal mode")) {
      currentLevel = "off";
      return;
    }

    if (
      text.includes("caveman mode") ||
      text.includes("talk like caveman") ||
      text.includes("use caveman") ||
      text.includes("less tokens") ||
      text.includes("fewer tokens") ||
      text.includes("be brief")
    ) {
      currentLevel = "ultra";
    }
  });

  pi.on("before_agent_start", async () => {
    if (currentLevel === "off") return;

    return {
      message: {
        role: "user",
        content: [{ type: "text", text: `[${CAVEMAN_INSTRUCTIONS}]` }],
        display: false,
      },
    };
  });
}
