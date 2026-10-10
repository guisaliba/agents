// Verify the approved rendering tool boundary without model requests.
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { readFileSync, writeFileSync } from "node:fs";
import type { ExtensionAPI, ToolDefinition } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("test-visual-isolation", {
    description: "Render two independent visual sessions without inference",
    handler: async () => {
      const report: any = { passed: false, model_requests: 0, checks: [] };
      try {
        const root = process.env.PORT_VISUAL_TEST_SOURCE!;
        for (const group of ["svg", "mermaid"]) {
          const factory = (await import(pathToFileURL(`${root}/${group}_tools.ts`).href)).default;
          const collect = (id: string) => {
            const tools = new Map<string, ToolDefinition>();
            factory({ registerTool: (t: ToolDefinition) => tools.set(t.name, t) } as unknown as ExtensionAPI, id);
            return tools;
          };
          const a = collect(`test-a-${group}`), b = collect(`test-b-${group}`);
          const call = (tools: Map<string, ToolDefinition>, name: string, args: any) =>
            tools.get(name)!.execute("test", args, new AbortController().signal, undefined, {} as any) as Promise<any>;
          const sources = group === "svg" ? [
            '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="80"><rect width="160" height="80" fill="red"/></svg>',
            '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="80"><rect width="160" height="80" fill="blue"/></svg>'
          ] : ['graph LR\n A[Red] --> B[One]', 'graph LR\n C[Blue] --> D[Two]'];
          const wa = await call(a, `write_${group}`, {source: sources[0]});
          const wb = await call(b, `write_${group}`, {source: sources[1]});
          assert.notEqual(wa.details.path, wb.details.path, "Parallel sessions must not share source paths");
          assert.equal(readFileSync(wa.details.path, "utf8"), sources[0]);
          const [ra, rb] = await Promise.all([call(a, `render_${group}`, {}), call(b, `render_${group}`, {})]);
          assert.equal(ra.details.ok, true, JSON.stringify(ra.content));
          assert.equal(rb.details.ok, true, JSON.stringify(rb.content));
          const images = [ra, rb].map(r => r.content.find((c: any) => c.type === "image"));
          assert.ok(images.every(Boolean));
          assert.notEqual(images[0].data, images[1].data);
          const restored = await call(collect(`test-a-${group}`), `render_${group}`, {});
          assert.equal(restored.details.ok, true, "A resumed visual session must retain its source");
          assert.equal(restored.content.find((c: any) => c.type === "image").data, images[0].data);
          report.checks.push({group, source_paths_distinct: true, rendered_images_distinct: true,
            artifacts: [ra.details.path, rb.details.path]});
        }
        report.passed = true;
      } catch (error) {
        report.failure = error instanceof Error ? error.message : String(error);
      }
      writeFileSync(process.env.PORT_VISUAL_TEST_OUTPUT!, JSON.stringify(report, null, 2)+"\n");
      console.log(report.passed ? "PASS: isolated SVG and Mermaid renders" : "FAIL: "+report.failure);
    }
  });
}
