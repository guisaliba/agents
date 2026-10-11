#!/usr/bin/env python3
"""Live original Learn workflow through the real terminal and approved launcher.

A synthetic student answers through keyboard input. Test instrumentation only
observes public Pi events; it does not replace quiz/question tools or results.
"""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("memory_helpers", HERE/"verify-ai-memory.py")
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)
ANSI = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--memory-binary", type=Path, required=True)
    parser.add_argument("--memory-endpoint", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.agent_dir.resolve() == (Path.home()/".pi/agent").resolve():
        parser.error("Use the separate authenticated profile")
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=False)
    work = root/"fixture"
    work.mkdir()
    note = work/"lesson.md"
    note.write_text("# Existing synthetic lesson note\n\nPreserve this paragraph.\n")
    (work/"reference.md").write_text(
        "# Authorized lesson reference\nFor ordered real numbers and low <= high, clamp(x, low, high) returns low "
        "when x < low, high when x > high, and x otherwise. Equal bounds return that bound. "
        "For this lesson, low > high is an invalid interval and raises ValueError. "
        "The goal is to understand clamp(9, 2, 8) = 8, not NaN or incomparable types.\n")
    audit = root/"public-events.jsonl"
    observer = root/"test-observer.ts"
    observer.write_text('import {appendFileSync} from "node:fs"; export default function(pi:any) { '
        f'const log=(v:any)=>appendFileSync({json.dumps(str(audit))},JSON.stringify(v)+"\\n"); '
        'pi.on("tool_call",(e:any)=>{if(["quiz","ask_user_question","agent_spawn"].includes(e.toolName)) '
        'log({event:"call",name:e.toolName,id:e.toolCallId,input:e.input});}); '
        'pi.on("tool_result",(e:any)=>{if(["quiz","ask_user_question"].includes(e.toolName)) '
        'log({event:"result",name:e.toolName,id:e.toolCallId,details:e.details,isError:e.isError});}); '
        'pi.on("agent_settled",()=>log({event:"settled"})); }')
    proxy = root/"observed-pi"
    proxy.write_text(f'#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nreal={shutil.which("pi")!r}\n'
                     f'if a!=["--version"]: a[a.index("--"):a.index("--")]=["--extension",{str(observer)!r}]\n'
                     'os.execv(real,[real,*a])\n')
    proxy.chmod(0o700)
    command = [sys.executable, "-B", str(HERE/"launch.py"), "--no-context-files", "--agent-dir", str(args.agent_dir.resolve()),
               "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint,
               "--pi-binary", str(proxy), "--model", "openai/gpt-6.1-sol", "--subagents", "--ysk-model", "openai/gpt-6-luna"]
    report = {"complete": False, "synthetic_student": True, "native_ui": True, "checks": [], "answers": []}
    before = memory.shared_settings_stamp()
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 180, 0, 0))
    process = None
    try:
        process = subprocess.Popen(command, cwd=work, stdin=slave, stdout=slave, stderr=slave,
                                   start_new_session=True, env={**os.environ, "TERM": "xterm-256color"})
        os.close(slave)
        text = ""
        def drain(seconds=0.2):
            nonlocal text
            end = time.monotonic()+seconds
            while time.monotonic() < end:
                ready, _, _ = select.select([master], [], [], max(0, end-time.monotonic()))
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        return
                    text = (text+ANSI.sub("", chunk.decode("utf8", "replace")))[-60000:]
        drain(4)
        os.write(master, (f"/md-log {note}\r").encode())
        drain(1)
        prompt = (
            "/skill:teach This is a synthetic learner E2E test, not the real user's knowledge profile. "
            "Teach only the ordered-real-number clamp example in reference.md, using the original probe-plan-teach sequence. "
            "The student knows integer ordering but does not yet understand clamping. Use single-select quiz questions with "
            "short plain labels, and a single-select ask_user_question for the learning goal; this test student answers by keyboard. "
            "Keep the goal to clamp(9,2,8)=8. Probe only goal-relevant strands, then delegate reference verification to researcher, "
            "present the plan and wait for go-ahead. Then teach a short lesson, use quiz checks, and use /skill:visualize to delegate "
            "ONE Mermaid picture to coder; render, inspect, publish, and embed its PNG in the lesson. Treat the maker document as "
            "task instructions, not an additional role. At completion, say LEARN_WORKFLOW_COMPLETE. "
            "No network, credentials, dotenv files, environment dumps, dependencies, commits, or edits outside this fixture and "
            "visual staging. Subagent starts are automatically authorized."
        )
        os.write(master, (prompt+"\r").encode())
        handled = set()
        quiz_count = 0
        approved_plan = False
        last_settled = 0
        deadline = time.monotonic()+600
        pending_since = {}
        while time.monotonic() < deadline and process.poll() is None:
            drain(0.3)
            events = [json.loads(line) for line in audit.read_text().splitlines()] if audit.exists() else []
            for event in events:
                if event.get("event") != "call" or event.get("name") not in ("quiz", "ask_user_question") or event["id"] in handled:
                    continue
                params = event["input"]
                pending_since.setdefault(event["id"], time.monotonic())
                if time.monotonic()-pending_since[event["id"]] > 30:
                    report["ui_diagnostics"] = {"question_visible": params["question"] in text,
                        "navigation_visible": "navigate" in text,
                        "option_labels_visible": [o["label"] in text for o in params.get("options", [])]}
                    raise AssertionError("Native question frame could not be matched within 30 seconds")
                if params.get("multiSelect"):
                    raise AssertionError("Synthetic student requires the requested single-select UI")
                options = params.get("options", [])
                if not options:
                    raise AssertionError("Synthetic student requires the requested options-based UI")
                if event["name"] == "quiz":
                    value = params["correctAnswer"]
                    if isinstance(value, list):
                        raise AssertionError("Synthetic student requires a single correct choice")
                    label = next(o["label"] for o in options if o.get("value", o["label"]) == value)
                    matches = list(re.finditer(r"([1-9])\.\s*"+re.escape(label), text))
                    if params["question"] not in text or not matches:
                        continue
                    quiz_count += 1
                    # Establish a floor, then an honest ceiling; subsequent checks answer correctly.
                    index = len(options) if quiz_count == 2 else int(matches[-1].group(1))-1
                    outcome = "dont_know" if quiz_count == 2 else "correct"
                else:
                    if params["question"] not in text:
                        continue
                    index = 0
                    outcome = "first_goal_option"
                    if "plan" in params["question"].lower() and any(word in options[0]["label"].lower() for word in ("start", "proceed", "go ahead")):
                        approved_plan = True
                os.write(master, b"\x1b[B"*index+b"\r")
                drain(0.3)
                if event["name"] == "quiz":
                    os.write(master, b"\r")  # Native feedback acknowledgement.
                handled.add(event["id"])
                report["answers"].append({"tool": event["name"], "question": params["question"], "answer_policy": outcome})
                text = ""
            settled = sum(e.get("event") == "settled" for e in events)
            if settled > last_settled:
                last_settled = settled
                drain(0.3)
                content = note.read_text()
                if "LEARN_WORKFLOW_COMPLETE" in content and "![[" in content and list((work/"viz").glob("*.png")):
                    os.write(master, b"\x04")
                    drain(1)
                    break
                if quiz_count >= 2 and any(e.get("name") == "agent_spawn" and e["input"].get("type") == "researcher" for e in events):
                    os.write(master, b"Go ahead with the presented plan. Finish the short lesson, quiz checks, and one verified PNG embed.\r")
                    approved_plan = True
        if process.poll() is None:
            process.wait(timeout=10)
        if process.returncode != 0:
            raise AssertionError("The native teaching session did not complete and exit normally")
        content = note.read_text()
        events = [json.loads(line) for line in audit.read_text().splitlines()]
        results = [e for e in events if e.get("event") == "result"]
        if not all(any(e.get("name") == name and e.get("details", {}).get("status") == "answered" for e in results) for name in ("quiz", "ask_user_question")):
            raise AssertionError("Original quiz and question tools did not receive native UI answers")
        types = {e["input"].get("type") for e in events if e.get("name") == "agent_spawn"}
        if not {"researcher", "coder"} <= types or not approved_plan:
            raise AssertionError("Research, plan approval, and coder visual delegation were not all observed")
        if not content.startswith("# Existing synthetic lesson note\n\nPreserve this paragraph.\n"):
            raise AssertionError("The lesson logger removed existing note content")
        if "![[" not in content or "LEARN_WORKFLOW_COMPLETE" not in content:
            raise AssertionError("Completed lesson and image embed are absent from the note")
        report["complete"] = True
        report["checks"] = [{"name": n, "passed": True} for n in (
            "native quiz and goal answers", "researcher and coder delegation", "plan checkpoint approved",
            "rendered PNG embedded in logged lesson", "existing note preserved", "normal terminal exit")]
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError) as error:
        report["failure"] = str(error) if isinstance(error, AssertionError) else type(error).__name__
        print("FAIL:", report["failure"], flush=True)
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
        os.close(master)
        report["shared_settings_metadata_unchanged"] = memory.shared_settings_stamp() == before
        if not report["shared_settings_metadata_unchanged"]:
            report["complete"] = False
        (root/"result.json").write_text(json.dumps(report, indent=2)+"\n")
    if report["complete"]:
        print("PASS: original Learn teaching UI, delegation, render and logged PNG", flush=True)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
