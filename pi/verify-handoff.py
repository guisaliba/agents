#!/usr/bin/env python3
"""Verify automatic handoff injection through the installed port, without paid requests.

The real memory service and unmodified generated hook run normally. Only the
provider is a synthetic in-process stream. No credentials are used or inspected.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.request
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("resource_test", HERE/"verify-resources.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def rpc(endpoint, tool, arguments):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": tool, "arguments": arguments}}
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(endpoint+"/mcp", data=json.dumps(body).encode(),
                                    headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream"})
    with opener.open(request, timeout=15) as response:
        result = json.load(response)
    if result.get("error") or result.get("result", {}).get("isError"):
        raise RuntimeError("Memory handoff operation failed")
    content = result["result"].get("content", [])
    return json.loads(next(e["text"] for e in content if e.get("type") == "text"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repository-cwd", type=Path, help="Also verify the real repository scope")
    args = parser.parse_args()
    root = args.root.resolve()
    endpoint = json.loads((root/"install.json").read_text())["endpoint"]
    report = {"complete": False, "live_model_requests": 0, "synthetic_provider": True}
    nonce = "PORT-HANDOFF-"+uuid.uuid4().hex
    scope = {"workspace": "pi-port-verification", "project": "handoff-"+uuid.uuid4().hex[:12]}
    if args.repository_cwd:
        import tomllib
        marker = tomllib.loads((args.repository_cwd/".ai-memory.toml").read_text())
        scope = {"workspace": marker["workspace"], "project": marker["project"]}
    with tempfile.TemporaryDirectory(prefix="pi-handoff-test-") as temporary:
        work = Path(temporary)
        (work/".ai-memory.toml").write_text('workspace = "'+scope["workspace"]+'"\nproject = "'+scope["project"]+'"\n')
        audit = work/"provider-audit.jsonl"
        fixture = work/"synthetic-provider.ts"
        fixture.write_text('''import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import { appendFileSync } from "node:fs";
export default function(pi:any) {
 pi.registerProvider("openai", {
  api: "openai-responses", apiKey: "synthetic-fixture-not-a-live-credential",
  baseUrl: "http://127.0.0.1:9",
  streamSimple: (model:any, context:any) => {
   const stream = createAssistantMessageEventStream();
   const message:any = {role:"assistant",provider:model.provider,model:model.id,api:model.api,
    timestamp:Date.now(),content:[{type:"text",text:"SYNTHETIC_HANDOFF_TEST_DONE"}],stopReason:"stop",
    usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
   appendFileSync(AUDIT, JSON.stringify({handoff_seen:JSON.stringify(context.messages).includes(NONCE)})+"\\n");
   queueMicrotask(()=>{stream.push({type:"start",partial:message});stream.push({type:"done",reason:"stop",message});stream.end();});
   return stream;
  }
 });
}
'''.replace("AUDIT", json.dumps(str(audit))).replace("NONCE", json.dumps(nonce)))
        proxy = work/"observed-pi"
        real = str(root/"packages/runtime/node_modules/.bin/pi")
        proxy.write_text('#!/usr/bin/env python3\nimport os,sys\na=sys.argv[1:]\n'
                         +'if a!=["--version"]: a[a.index("--"):a.index("--")]=["--extension",'+repr(str(fixture))+']\n'
                         +'os.execv('+repr(real)+',['+repr(real)+',*a])\n')
        proxy.chmod(0o700)
        cwd = args.repository_cwd.resolve() if args.repository_cwd else work
        created = rpc(endpoint, "memory_handoff_begin", {**scope, "summary": nonce+" Synthetic automatic-hook verification.", "cwd": str(cwd), "shared": False})
        report["created"] = created
        report["scope"] = scope
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+"\n")
        command = [str(HERE.parent/"bin/pi-port"), "--pi-binary", str(proxy), "--mode", "rpc", "--no-session"]
        previous = os.environ.get("PI_PORT_HOME")
        os.environ["PI_PORT_HOME"] = str(root)
        try:
            for _ in range(2):
                session = helpers.Session(command, cwd)
                try:
                    session.request("set_auto_retry", enabled=False)
                    session.prompt("Complete the synthetic handoff hook check. No tools or delegation.")
                finally:
                    session.close()
            calls = [json.loads(line) for line in audit.read_text().splitlines()]
            if calls != [{"handoff_seen": True}, {"handoff_seen": False}]:
                raise AssertionError("Automatic injection or single-use consumption failed")
            remaining = rpc(endpoint, "memory_handoff_list", scope)
            if any(h.get("summary", "").startswith(nonce) for h in remaining.get("handoffs", [])):
                raise AssertionError("The consumed fixture remains open")
            # Session-end legitimately creates a new automatic handoff. It is not
            # the manual fixture and must not be treated as a duplicate delivery.
            report["successor_handoffs"] = len(remaining.get("handoffs", []))
            report.update(complete=True, checks=["first prompt receives handoff automatically", "next session does not receive it again", "no manual accept or note-file fallback"], provider_calls=calls)
        finally:
            if previous is None:
                os.environ.pop("PI_PORT_HOME", None)
            else:
                os.environ["PI_PORT_HOME"] = previous
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    print("PASS: automatic handoff injection and single-use consumption; no live model requests")


if __name__ == "__main__":
    main()
