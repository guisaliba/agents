// Approved child-session integrations. Staged beside the manager, Learn and YSK.
// Requirement: isolated Learn visuals and Luna/max child-note relay, with six roles.
import { join, dirname } from "node:path";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { getAgentDir, type ExtensionContext, type SessionManager } from "@earendil-works/pi-coding-agent";
import mermaid from "../learn/extensions/visual-tools/tools/mermaid_tools.ts";
import svg from "../learn/extensions/visual-tools/tools/svg_tools.ts";
import ysk from "../ysk/index.ts";

export function childSystemPrompt(): string {
  return readFileSync(join(dirname(fileURLToPath(import.meta.url)), "port-instructions.md"), "utf8") +
    "\nNever read secret values, dotenv credential files, auth.json, SSH/AWS credentials, or dump environment variables. Never copy or link authentication. Use only the authorized fixture or project files.\n";
}

export function childToolNames(role: string): string[] {
  return role === "coder" ? ["write_mermaid", "edit_mermaid", "render_mermaid", "write_svg", "edit_svg", "render_svg"] : [];
}

export function childExtensions(root: ExtensionContext, threadPath: string, role: string,
  session: SessionManager, allowed: Set<string>) {
  const factories: Array<(pi: any) => void> = [];
  const id = session.getSessionId();
  if (role === "coder") {
    // Register only allowed tools, even when a user narrows the coder's loadout.
    const filtered = (pi: any) => ({registerTool: (tool: any) => {
      if (allowed.has(tool.name)) pi.registerTool(tool);
    }});
    if (["write_mermaid", "edit_mermaid", "render_mermaid"].some(n => allowed.has(n)))
      factories.push(pi => mermaid(filtered(pi) as any, id));
    if (["write_svg", "edit_svg", "render_svg"].some(n => allowed.has(n)))
      factories.push(pi => svg(filtered(pi) as any, id));
  }
  const model = process.env.PI_PORT_CHILD_YSK_MODEL?.trim();
  if (model) {
    const artifacts = join(root.sessionManager.getSessionDir(), "artifacts", root.sessionManager.getSessionId());
    factories.push(pi => ysk(pi, {
      stateDirectory: join(artifacts, "child-observers", id),
      relayInbox: join(artifacts, "you-should-know-inbox"),
      name: threadPath,
      observerModel: model,
      observerThinking: "max",
      parentStateFile: join(getAgentDir(), "you-should-know", "state.json"),
    }));
  }
  return factories;
}
