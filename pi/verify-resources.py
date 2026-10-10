#!/usr/bin/env python3
"""Check selected resources through the real launcher without model requests."""
import argparse
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
memory = load("memory_helpers", HERE/"verify-ai-memory.py")


class Session(memory.PiSession):
    def __init__(self, command, cwd):
        self.events = []
        self.notifications = []
        self.records = queue.Queue()
        self.process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.state = self.request("get_state")
        except BaseException:
            self.close()
            raise

    def receive(self, deadline):
        record = super().receive(deadline)
        if record.get("type") == "extension_ui_request" and record.get("method") == "notify":
            self.notifications.append(record)
        return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--memory-binary", type=Path, required=True)
    parser.add_argument("--memory-endpoint", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pi-binary", default="pi", help="Installed Pi executable; no global install is required")
    parser.add_argument("--subagents", action="store_true")
    parser.add_argument("--ysk-model", choices=("openai/gpt-6.1-sol", "openai/gpt-6-luna"))
    args = parser.parse_args()
    agent = args.agent_dir.resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use the separate Pi test directory")
    report = {"complete": False, "port_complete": False, "model_requests": 0, "checks": []}
    before = memory.shared_settings_stamp()
    session = None
    try:
        with contextlib.ExitStack() as cleanup:
            root = Path(cleanup.enter_context(tempfile.TemporaryDirectory(prefix="pi-resource-check-")))
            audit = root/"resources.json"
            observer = root/"observer.ts"
            observer.write_text('import {writeFileSync} from "node:fs"; export default function(pi:any) { '
                                'pi.on("session_start",()=>writeFileSync('
                                +json.dumps(str(audit))+',JSON.stringify({active:pi.getActiveTools(),registered:pi.getAllTools().map((t:any)=>t.name)}))); }')
            proxy = root/"observed-pi"
            proxy.write_text(f'#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nreal={shutil.which(args.pi_binary)!r}\n'
                             f'if a!=["--version"]: a[a.index("--"):a.index("--")]=["--extension",{str(observer)!r}]\n'
                             'os.execv(real,[real,*a])\n')
            proxy.chmod(0o700)
            command = [sys.executable, "-B", str(HERE/"launch.py"), "--agent-dir", str(agent),
                       "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint,
                       "--pi-binary", str(proxy), "--model", "openai/gpt-6-luna", "--mode", "rpc", "--no-session"]
            if args.ysk_model:
                command += ["--ysk-model", args.ysk_model]
            if args.subagents:
                command += ["--subagents"]
            session = Session(command, root)
            cleanup.callback(session.close)
            commands = session.request("get_commands").get("commands", [])
            expected = {line.split("\t")[0] for line in (HERE/"skills.tsv").read_text().splitlines()
                        if line and not line.startswith("#")}
            skills = {c["name"].removeprefix("skill:") for c in commands if c.get("source") == "skill"}
            if skills != expected:
                raise AssertionError("The launcher did not load exactly the 20 approved skills")
            report["checks"].append({"name": "exact approved skill discovery", "passed": True, "skills": sorted(skills)})
            names = {c["name"] for c in commands if c.get("source") == "extension"}
            expected_commands = {"md-log", "md-unlog"} | ({"ysk"} if args.ysk_model else set()) | ({"agents"} if args.subagents else set())
            if names != expected_commands:
                raise AssertionError("Unexpected extension command discovery")
            tools = json.loads(audit.read_text())
            if (not {"ask_user_question", "quiz"} <= set(tools["active"])
                    or any(t not in ("read", "bash", "edit", "write", "ask_user_question", "quiz")
                           and not t.startswith("memory_")
                           and not (args.subagents and t.startswith("agent_")) for t in tools["active"])):
                raise AssertionError("Approved Learn tools are missing or unselected tools are active")
            if any(t in tools["registered"] for t in ("subagent", "write_svg", "edit_svg", "render_svg", "write_mermaid", "edit_mermaid", "render_mermaid")):
                raise AssertionError("A deferred subagent or child visual tool was enabled")
            if args.subagents and not {"agent_types", "agent_spawn", "agent_steer", "agent_stop"} <= set(tools["active"]):
                raise AssertionError("Approved subagent controls are not active")
            report["checks"].append({"name": "Approved tools and subagent selection", "passed": True,
                                     "active_tools": sorted(tools["active"]), "commands": sorted(names)})
            if args.ysk_model:
                session.request("prompt", message="/ysk status")
                if not any(f"model {args.ysk_model}" in n.get("message", "") and "thinking max" in n.get("message", "")
                           for n in session.notifications):
                    raise AssertionError("YSK did not select the explicit approved side model and max thinking")
                session.request("prompt", message="/ysk test")
                sample = next((n["message"] for n in reversed(session.notifications)
                               if "[ysk:" in n.get("message", "")), None)
                if not sample or "This is a test note from /ysk test." not in sample:
                    raise AssertionError("The upstream sample note was not delivered through RPC")
                import re
                note_id = re.search(r"\[ysk:([^]]+)\]", sample).group(1)
                session.request("prompt", message=f"/ysk answer {note_id} knew")
                session.request("prompt", message=f"/ysk answer {note_id} undo")
                session.request("prompt", message=f"/ysk answer {note_id} dismiss")
                report["checks"].append({"name": "upstream sample RPC note and answer commands", "passed": True,
                                         "sample_note_not_model_generated": True, "side_model": args.ysk_model})
            report["complete"] = True
    except (AssertionError, OSError, RuntimeError, TimeoutError, queue.Empty) as error:
        report["failure"] = str(error) if isinstance(error, AssertionError) else type(error).__name__
        print("FAIL:", report["failure"], flush=True)
    finally:
        if session:
            session.close()
        report["shared_settings_metadata_unchanged"] = memory.shared_settings_stamp() == before
        if not report["shared_settings_metadata_unchanged"]:
            report["complete"] = False
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+"\n")
    if report["complete"]:
        print("PASS: exact approved resource loading; no model requests", flush=True)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
