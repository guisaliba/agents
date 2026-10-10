// Test-only detector calls for the approved paired quality pilot.
// Source: the approved 72-request pilot; upstream index.ts:61–62,242–266.
// This does not load YSK state, deliver notes, or change production settings.
import { readFileSync, writeFileSync, realpathSync } from "node:fs";
import { resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("ysk-benchmark", {
    description: "Run one synthetic observer-quality request",
    handler: async (argument, ctx) => {
      const root = realpathSync(process.env.YSK_BENCH_DIR!);
      const path = realpathSync(argument.trim());
      if (!path.startsWith(root + sep) || !path.endsWith(".job.json")) throw new Error("Invalid benchmark input");
      const job = JSON.parse(readFileSync(path, "utf8"));
      const output = resolve(job.output);
      if (!output.startsWith(root + sep)) throw new Error("Invalid benchmark output");
      const result: any = { id: job.id, case: job.case, repetition: job.repetition,
        requested_model: job.model, requested_reasoning: job.reasoning, success: false };
      const started = Date.now();
      try {
        const [provider, ...parts] = job.model.split("/");
        const model = ctx.modelRegistry.find(provider, parts.join("/"));
        if (!model) throw new Error("Unavailable benchmark model");
        const template = readFileSync(job.template, "utf8");
        const prompt = template.replace("{{SEEN}}", "(nothing yet)").replace("{{KNOWN}}", "(nothing yet)");
        const context = { systemPrompt: job.system_prompt, messages: [...job.messages,
          { role: "user" as const, content: [{ type: "text" as const, text: prompt }], timestamp: 0 }] };
        const response = await ctx.modelRegistry.streamSimple(model, context, {
          signal: AbortSignal.timeout(300000),
          sessionId: ctx.sessionManager.getSessionId() + ":" + job.id,
          reasoning: job.reasoning,
          toolChoice: "none",
          onPayload: (value: any) => {
            result.wire_model = value.model;
            result.wire_reasoning = value.reasoning?.effort ?? value.reasoning_effort;
            result.wire_tool_choice = value.tool_choice;
            return undefined;
          },
        }).result();
        result.provider = response.provider;
        result.model = response.model;
        result.stop_reason = response.stopReason;
        result.usage = response.usage;
        result.text = response.content.filter((c: any) => c.type === "text").map((c: any) => c.text).join("\n");
        result.success = response.provider === provider && response.model === model.id
          && result.wire_reasoning === job.reasoning && result.wire_model === model.id
          && response.stopReason === "stop" && result.text.length > 0;
        if (!result.success) result.error_category = "provider-result-or-wire-contract";
      } catch (error) {
        // Never retain raw provider errors: they can contain authentication data.
        result.error_category = error instanceof Error ? error.name : "unknown-error";
      }
      result.elapsed_ms = Date.now() - started;
      writeFileSync(output, JSON.stringify(result, null, 2) + "\n", { mode: 0o600 });
    },
  });
}
