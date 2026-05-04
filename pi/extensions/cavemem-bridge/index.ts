import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { execFile } from "node:child_process";
import { readdir, realpath } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

type TransportCommand = {
  command: string;
  args: string[];
};

let cachedTransportCommand: TransportCommand | undefined;

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function resolveCavememTransportCommand(): Promise<TransportCommand> {
  const { stdout } = await execFileAsync("which", ["cavemem"]);
  const cavememBin = stdout.trim().split("\n")[0];

  if (!cavememBin) {
    throw new Error("cavemem was not found on PATH");
  }

  const realBin = await realpath(cavememBin);
  const distDir = dirname(realBin);
  const entries = await readdir(distDir);
  const serverEntry = entries.find((entry) => /^server-.*\.js$/.test(entry));

  if (!serverEntry) {
    return { command: "cavemem", args: ["mcp"] };
  }

  // cavemem@0.1.3's `cavemem mcp` command imports the server module but does
  // not start it. Executing the bundled server file directly starts MCP stdio.
  return { command: process.execPath, args: [join(distDir, serverEntry)] };
}

async function getCavememTransportCommand(): Promise<TransportCommand> {
  if (cachedTransportCommand) return cachedTransportCommand;

  cachedTransportCommand = await resolveCavememTransportCommand();
  return cachedTransportCommand;
}

async function callCavememTool(name: string, args: Record<string, JsonValue>, signal?: AbortSignal) {
  const transport = new StdioClientTransport(await getCavememTransportCommand());

  const client = new Client(
    { name: "pi-cavemem-bridge", version: "0.1.0" },
    { capabilities: {} },
  );

  try {
    if (signal?.aborted) throw new Error("aborted");
    await client.connect(transport);
    return await client.callTool({ name, arguments: args });
  } finally {
    await client.close().catch(() => undefined);
  }
}

async function executeCavememTool(name: string, args: Record<string, JsonValue>, signal?: AbortSignal) {
  try {
    const result = await callCavememTool(name, args, signal);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      details: { tool: name },
    };
  } catch (error) {
    const message = `cavemem bridge error: ${errorMessage(error)}. Ensure cavemem is installed and available on PATH, then run \`cavemem status\`.`;
    return {
      content: [{ type: "text", text: message }],
      details: { tool: name, error: errorMessage(error) },
      isError: true,
    };
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "cavemem_search",
    label: "Cavemem Search",
    description: "Search cavemem memory using compact progressive-disclosure results.",
    parameters: Type.Object({
      query: Type.String({ description: "Natural-language search query." }),
      limit: Type.Optional(Type.Number({ description: "Maximum number of results." })),
    }),
    async execute(_toolCallId, params, signal) {
      return executeCavememTool("search", params as Record<string, JsonValue>, signal);
    },
  });

  pi.registerTool({
    name: "cavemem_list_sessions",
    label: "Cavemem List Sessions",
    description: "List recent cavemem sessions in reverse chronological order.",
    parameters: Type.Object({
      limit: Type.Optional(Type.Number({ description: "Maximum number of sessions." })),
    }),
    async execute(_toolCallId, params, signal) {
      return executeCavememTool("list_sessions", params as Record<string, JsonValue>, signal);
    },
  });

  pi.registerTool({
    name: "cavemem_timeline",
    label: "Cavemem Timeline",
    description: "Get chronological observation identifiers for a cavemem session.",
    parameters: Type.Object({
      session_id: Type.String({ description: "Cavemem session id." }),
      around_id: Type.Optional(Type.Number({ description: "Observation id to center around." })),
      limit: Type.Optional(Type.Number({ description: "Maximum number of observations." })),
    }),
    async execute(_toolCallId, params, signal) {
      return executeCavememTool("timeline", params as Record<string, JsonValue>, signal);
    },
  });

  pi.registerTool({
    name: "cavemem_get_observations",
    label: "Cavemem Get Observations",
    description: "Fetch full cavemem observation bodies by id.",
    parameters: Type.Object({
      ids: Type.Array(Type.Number(), { description: "Observation ids." }),
      expand: Type.Optional(Type.Boolean({ description: "Return expanded human-readable content." })),
    }),
    async execute(_toolCallId, params, signal) {
      return executeCavememTool("get_observations", params as Record<string, JsonValue>, signal);
    },
  });

  pi.registerCommand("cavemem-status", {
    description: "Show cavemem status.",
    handler: async (_args, ctx) => {
      ctx.ui.notify("Run `cavemem status` in a shell for the full wiring dashboard.", "info");
    },
  });
}
