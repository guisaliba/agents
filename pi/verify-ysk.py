#!/usr/bin/env python3
"""Verify live YSK inference through the launcher with synthetic read-only work.

The observer uses a selected real primary model. No subagent extension is used.
Only non-secret check metadata is retained, not raw provider errors or payloads.
"""
import argparse
import contextlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import queue
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("resource_checks", HERE/"verify-resources.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def ui_smoke(args, root, report):
    ready = root/"ui-ready"
    requests = root/"ui-requests"
    observer = root/"ui-observer.ts"
    observer.write_text('import {writeFileSync,appendFileSync} from "node:fs"; export default function(pi:any) { '
        'pi.on("session_start",()=>writeFileSync('+json.dumps(str(ready))+',"ready")); '
        'pi.on("before_provider_request",()=>appendFileSync('+json.dumps(str(requests))+',"request\\n")); }')
    proxy = root/"ui-pi"
    proxy.write_text(f'#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nreal={shutil.which("pi")!r}\n'
                     f'if a!=["--version"]: a[a.index("--"):a.index("--")]=["--extension",{str(observer)!r}]\n'
                     'os.execv(real,[real,*a])\n')
    proxy.chmod(0o700)
    command = [sys.executable, "-B", str(HERE/"launch.py"), "--no-context-files", "--agent-dir", str(args.agent_dir.resolve()),
               "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint,
               "--pi-binary", str(proxy), "--model", args.model, "--ysk-model", args.model, "--no-session"]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
    child = subprocess.Popen(command, cwd=root, env={**os.environ, "TERM": "xterm-256color"},
                             stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    received = bytearray()

    def wait_for(predicate):
        deadline = time.monotonic()+30
        while time.monotonic() < deadline and child.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    received.extend(os.read(master, 65536))
                except OSError:
                    break
            visible = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", received.decode("utf-8", "replace"))
            if predicate(visible):
                return
        raise AssertionError("The YSK terminal interaction did not reach its expected display")

    try:
        wait_for(lambda _: ready.exists())
        time.sleep(0.2)
        os.write(master, b"/ysk test\r")
        wait_for(lambda text: "This is a test note from /ysk test." in text)
        received.clear()
        os.write(master, b"/ysk\r")
        wait_for(lambda text: "1 Learn more" in text)
        os.write(master, b"\r")
        wait_for(lambda text: "Nothing is wrong." in text)
        os.write(master, b"\r")
        time.sleep(0.2)
        os.write(master, b"\x04")
        deadline = time.monotonic()+15
        while time.monotonic() < deadline and child.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    os.read(master, 65536)
                except OSError:
                    break
        child.wait(timeout=2)
        if child.returncode != 0 or requests.exists():
            raise AssertionError("The sample UI made a model request or did not exit normally")
        report["checks"].append({"name": "terminal sample widget, menu, explanation, and normal exit", "passed": True,
                                 "model_requests": 0, "sample_not_model_generated": True})
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait(timeout=10)
        os.close(master)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--memory-binary", type=Path, required=True)
    parser.add_argument("--memory-endpoint", required=True)
    parser.add_argument("--model", choices=("openai/gpt-6.1-sol", "openai/gpt-6-luna"), default="openai/gpt-6-luna")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    agent = args.agent_dir.resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use the separate authenticated test directory")
    report = {"complete": False, "port_complete": False, "subagent_extension_installed": False,
              "primary_model": args.model, "observer_model": args.model, "checks": []}
    before = checks.memory.shared_settings_stamp()
    try:
        with contextlib.ExitStack() as cleanup:
            root = Path(cleanup.enter_context(tempfile.TemporaryDirectory(prefix="pi-ysk-live-")))
            receipt = root/"synthetic-receipt.txt"
            receipt.write_text("This is synthetic observer test data. There is no project change to review.\n")
            audit = root/"turns.jsonl"
            observer = root/"test-gate.ts"
            observer.write_text('import {appendFileSync} from "node:fs"; export default function(pi:any) { '
                'const log=(v:any)=>appendFileSync('+json.dumps(str(audit))+',JSON.stringify(v)+"\\n"); '
                'pi.on("tool_call",(e:any)=>{ if(e.toolName!=="read" || e.input.path!=='+json.dumps(str(receipt))
                +') return {block:true,reason:"Only the synthetic receipt read is permitted"}; log({type:"read"}); }); '
                'pi.on("turn_end",(e:any)=>log({type:"turn",index:e.turnIndex})); '
                'pi.on("session_start",(_e:any,ctx:any)=>log({type:"session",id:ctx.sessionManager.getSessionId(),tools:pi.getActiveTools()})); }')
            proxy = root/"observed-pi"
            proxy.write_text(f'#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nreal={shutil.which("pi")!r}\n'
                             f'if a!=["--version"]: a[a.index("--"):a.index("--")]=["--extension",{str(observer)!r}]\n'
                             'os.execv(real,[real,*a])\n')
            proxy.chmod(0o700)
            command = [sys.executable, "-B", str(HERE/"launch.py"), "--no-context-files", "--agent-dir", str(agent),
                       "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint,
                       "--pi-binary", str(proxy), "--model", args.model, "--ysk-model", args.model,
                       "--mode", "rpc", "--no-session"]
            client = checks.Session(command, root)
            cleanup.callback(client.close)
            report["session"] = client.state["sessionId"]
            log_file = agent/"you-should-know/checks.jsonl"
            offset = log_file.stat().st_size if log_file.exists() else 0
            client.request("prompt", message="/ysk on")
            messages = client.prompt("This is a trivial product verification, not a lesson or repository task. "
                f"Read {receipt} exactly seven times using read. Make exactly one read call per assistant turn. "
                "Wait for each result before the next call. Do not batch calls, load skills, ask questions, "
                "or use other tools. After the seventh result, reply only YSK_SYNTHETIC_MAIN_COMPLETE.")
            assistants = [m for m in messages if m.get("role") == "assistant"]
            provider, model = args.model.split("/", 1)
            if (not assistants or any(m.get("provider") != provider or m.get("model") != model for m in assistants)
                    or not any("YSK_SYNTHETIC_MAIN_COMPLETE" in checks.memory.text(m) for m in assistants)):
                raise AssertionError("The selected primary model did not complete the synthetic work")
            deadline = time.monotonic()+150
            records = []
            while time.monotonic() < deadline:
                if log_file.exists():
                    with log_file.open("rb") as stream:
                        stream.seek(offset)
                        raw = stream.read()
                    records = [json.loads(line) for line in raw.splitlines() if line.strip()]
                    found = [r for r in records if r.get("event") == "check"]
                    if found:
                        break
                time.sleep(0.1)
            else:
                raise AssertionError("YSK did not finish a scheduled observer check")
            evidence = [{key: r.get(key) for key in ("step", "outcome", "provider", "model", "thinking", "usage", "stopReason")}
                        for r in found]
            report["observer_checks"] = evidence
            if any(r["provider"] != provider or r["model"] != model or r["outcome"] not in ("none", "shown")
                   or r["stopReason"] in ("error", "aborted") for r in evidence):
                raise AssertionError("The live observer did not succeed with the selected exact model")
            events = [json.loads(line) for line in audit.read_text().splitlines()]
            if sum(e["type"] == "read" for e in events) != 7 or not any(e.get("index") == 6 for e in events):
                raise AssertionError("The expected real tool steps did not trigger YSK")
            if any("subagent" in e.get("tools", []) for e in events):
                raise AssertionError("A deferred subagent tool was enabled")
            report["checks"] = [{"name": "seven controlled real Pi reads", "passed": True},
                                {"name": "scheduled live side inference on the exact approved model", "passed": True},
                                {"name": "no subagent tool is active", "passed": True}]
            client.close()
            ui_smoke(args, root, report)
            report["complete"] = True
    except (AssertionError, OSError, RuntimeError, TimeoutError, subprocess.SubprocessError, queue.Empty) as error:
        report["failure"] = str(error) if isinstance(error, AssertionError) else type(error).__name__
        print("FAIL:", report["failure"], flush=True)
    finally:
        report["shared_settings_metadata_unchanged"] = checks.memory.shared_settings_stamp() == before
        if not report["shared_settings_metadata_unchanged"]:
            report["complete"] = False
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+"\n")
    if report["complete"]:
        print("PASS: real main model and real YSK observer; no subagent system", flush=True)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
