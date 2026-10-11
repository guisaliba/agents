#!/usr/bin/env python3
"""Check normal and controlled instruction discovery through native Pi and a managed child.

Only the provider is synthetic. No live credentials or paid requests are used.
The fixture has its own project marker, so it cannot consume the real handoff.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("resources", HERE/"verify-resources.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    report = {"complete": False, "live_model_requests": 0, "synthetic_provider": True, "cases": []}
    with tempfile.TemporaryDirectory(prefix="pi-context-test-") as temporary:
        work = Path(temporary)
        nested = work/"nested"
        nested.mkdir()
        (work/"AGENTS.md").write_text("Parent project instruction: PORT_PARENT_CONTEXT_MARKER.\n")
        (nested/"AGENTS.md").write_text("Nested project instruction: PORT_NESTED_CONTEXT_MARKER.\n")
        (work/".ai-memory.toml").write_text('workspace = "pi-port-verification"\nproject = "context-'+uuid.uuid4().hex+'"\n')
        audit = work/"audit.jsonl"
        extension = work/"synthetic.ts"
        proxy = work/"observed-pi"
        real = str(root/"packages/runtime/node_modules/.bin/pi")
        proxy.write_text('#!/usr/bin/env python3\nimport os,sys\na=sys.argv[1:]\n'
                         +'if a != ["--version"]: a[a.index("--"):a.index("--")]=["--extension",'+repr(str(extension))+']\n'
                         +'os.execv('+repr(real)+',['+repr(real)+',*a])\n')
        proxy.chmod(0o700)
        previous = os.environ.get("PI_PORT_HOME")
        os.environ["PI_PORT_HOME"] = str(root)
        try:
            for disabled in (False, True):
                audit.unlink(missing_ok=True)
                (nested/"AGENTS.md").write_text("Nested project instruction: PORT_NESTED_CONTEXT_MARKER.\n")
                extension.write_text('''import {createAssistantMessageEventStream} from "@earendil-works/pi-ai";
import {appendFileSync} from "node:fs";
export default function(pi:any) {
 let started = false;
 pi.registerProvider("openai", {api:"openai-responses", apiKey:"synthetic-fixture-not-a-live-credential",
  baseUrl:"http://127.0.0.1:9", streamSimple:(model:any,context:any)=> {
   const stream=createAssistantMessageEventStream();
   const child=model.id === "gpt-6-luna";
   appendFileSync(AUDIT,JSON.stringify({child,parent_context:JSON.stringify(context.messages).includes("PORT_PARENT_CONTEXT_MARKER"),
    nested_context:JSON.stringify(context.messages).includes("PORT_NESTED_CONTEXT_MARKER"),
    child_fresh_context:JSON.stringify(context.messages).includes("PORT_CHILD_FRESH_CONTEXT_MARKER"),
    tool_results:context.messages.filter((m:any)=>m.role === "toolResult").map((m:any)=>m.content)})+"\\n");
   const spawn=!child && !started;
   if(spawn) {started=true; appendFileSync(CHILD_INSTRUCTIONS,"\\nPORT_CHILD_FRESH_CONTEXT_MARKER\\n");}
   const call={type:"toolCall",id:"context-check-call",name:"agent_spawn",
    arguments:{path:"/root/context-check",type:"coder",task:"Return the synthetic check result.",wait:true}};
   const message:any={role:"assistant",provider:model.provider,model:model.id,api:model.api,timestamp:Date.now(),
    content:spawn?[call]:[{type:"text",text:"SYNTHETIC_CONTEXT_CHECK_DONE"}],stopReason:spawn?"toolUse":"stop",
    usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}};
   queueMicrotask(()=>{stream.push({type:"start",partial:message});
    if(spawn){stream.push({type:"toolcall_start",contentIndex:0,partial:message});
     stream.push({type:"toolcall_end",contentIndex:0,toolCall:call,partial:message});}
    stream.push({type:"done",reason:message.stopReason,message});stream.end();});
   return stream;
  }});
}
'''.replace("AUDIT", json.dumps(str(audit))).replace("CHILD_INSTRUCTIONS", json.dumps(str(nested/"AGENTS.md"))))
                command = [str(HERE.parent/"bin/pi-port"), "--pi-binary", str(proxy), "--mode", "rpc"]
                if disabled:
                    command.append("--no-context-files")
                session = helpers.Session(command, nested)
                try:
                    session.request("set_auto_retry", enabled=False)
                    session.prompt("Complete the synthetic context-discovery check.")
                finally:
                    session.close()
                calls = [json.loads(line) for line in audit.read_text().splitlines()]
                case = {"discovery_enabled": not disabled, "provider_calls": calls}
                report["cases"].append(case)
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(report, indent=2)+"\n")
                if not any(call["child"] for call in calls):
                    raise AssertionError("No managed child reached the synthetic provider")
                if not all(call["parent_context"] == (not disabled) and call["nested_context"] == (not disabled) for call in calls):
                    raise AssertionError("Main/child instruction discovery does not match the selected policy")
                if not all(call["child_fresh_context"] == (not disabled) for call in calls if call["child"]):
                    raise AssertionError("Child did not discover instructions added after the parent snapshot")
        finally:
            if previous is None:
                os.environ.pop("PI_PORT_HOME", None)
            else:
                os.environ["PI_PORT_HOME"] = previous
    report["complete"] = True
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    print("PASS: parent/nested instructions reach main and managed child only in normal mode; no paid requests")


if __name__ == "__main__":
    main()
