#!/usr/bin/env python3
"""Verify the approved launcher through real Pi, retaining sanitized evidence.

Select either requested primary model or the approved isolated DeepSeek model.
A test-only Pi executable delegates
all work to real Pi and appends an observation/command-gate extension. No
instrumentation is installed or included in the daily launcher.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import sqlite3
import struct
import subprocess
import sys
import tempfile
import termios
import time
import uuid


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--memory-binary", type=Path, required=True)
    parser.add_argument("--memory-endpoint", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", choices=("openai/gpt-6.1-sol", "openai/gpt-6-luna",
                                            "opencode-go/deepseek-v4.1-flash"),
                        default="opencode-go/deepseek-v4.1-flash")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    launcher = load(directory/"launch.py", "launcher")
    memory = load(directory/"verify-ai-memory.py", "memory_verification")
    agent = args.agent_dir.expanduser().resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use the approved separately authenticated Pi test directory")
    args.memory_endpoint = launcher.local_endpoint(args.memory_endpoint)
    before = memory.shared_settings_stamp()
    watched = [Path.home()/".config/opencode/plugins/rtk.ts", Path.home()/".config/opencode/ai-memory.md",
               directory.parent/"AGENTS.md"]
    def stamps():
        paths = watched + list((Path.home()/".local/share/ai-memory").glob("*capture*"))
        return {str(p): (p.stat().st_ino, p.stat().st_mtime_ns, p.stat().st_size) for p in paths if p.is_file()}

    shared_before = stamps()
    report = {"checks": [], "complete": False, "daily_primary_models_verified": False,
              "model": args.model, "primary_model_verified": False,
              "launcher_sha256": hashlib.sha256((directory/"launch.py").read_bytes()).hexdigest(),
              "instructions_sha256": hashlib.sha256((directory/"AGENTS.md").read_bytes()).hexdigest(),
              "port_complete": False}
    base = [sys.executable, "-B", str(directory/"launch.py"), "--no-context-files", "--agent-dir", str(agent),
            "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint]
    model_option = ["--model" if args.model in launcher.PRIMARY_MODELS else "--verification-model", args.model]
    expected_provider, expected_model = args.model.split("/", 1)

    def passed(name, **evidence):
        report["checks"].append({"name": name, "passed": True, **evidence})
        print("PASS:", name, flush=True)

    try:
        for value in ("http://example.invalid:1234", "http://127.0.0.1:1234/mcp",
                      "http://127.0.0.1:1234?extra=1", "http://fixture@127.0.0.1:1234", "http://127.0.0.1:99999"):
            try:
                launcher.local_endpoint(value)
            except argparse.ArgumentTypeError:
                continue
            raise AssertionError("An invalid endpoint was accepted")
        passed("endpoint rejects remote hosts, credentials, paths, queries, and invalid ports")
        with tempfile.TemporaryDirectory(prefix="pi-launch-verification-") as temporary:
            root = Path(temporary)
            fixture = root/f"launcher-fixture-{uuid.uuid4().hex[:10]}"
            fixture.mkdir()
            safe_env = {"HOME": str(root), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
                        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
                        "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z"}
            for cmd in (["git", "init", "--quiet"], ["git", "config", "user.name", "Pi Fixture"],
                        ["git", "config", "user.email", "fixture@example.invalid"]):
                subprocess.run(cmd, cwd=fixture, env=safe_env, check=True, capture_output=True)
            for number in range(20):
                subprocess.run(["git", "commit", "--quiet", "--allow-empty", "-m", f"Launcher fixture commit {number:02d}"],
                               cwd=fixture, env=safe_env, check=True, capture_output=True)
            raw = subprocess.check_output(["git", "log", "-20"], cwd=fixture, env=safe_env, text=True)
            poisoned = fixture/".pi"
            (poisoned/"extensions").mkdir(parents=True)
            sentinel = root/"unapproved-extension-loaded"
            (poisoned/"extensions/unapproved.ts").write_text(f'import {{writeFileSync}} from "node:fs"; export default () => writeFileSync({json.dumps(str(sentinel))},"loaded");')
            (poisoned/"settings.json").write_text(json.dumps({"sessionDir": str(root/"unapproved-sessions")}))
            for file in (fixture/"AGENTS.md", poisoned/"SYSTEM.md", poisoned/"APPEND_SYSTEM.md"):
                file.write_text("PI_UNAPPROVED_FIXTURE_INSTRUCTIONS\n")
            (poisoned/"skills/unapproved").mkdir(parents=True)
            (poisoned/"skills/unapproved/SKILL.md").write_text('---\nname: unapproved-fixture\ndescription: PI_UNAPPROVED_FIXTURE_SKILL\n---\nNot selected.\n')
            audit = root/"launch-audit.json"
            observer_log = root/"observations.jsonl"
            observer = root/"test-observer.ts"
            observer.write_text('import {readFileSync,appendFileSync} from "node:fs";\n'
                'export default function(pi:any) {\n'
                f' const log=(v:any)=>appendFileSync({json.dumps(str(observer_log))},JSON.stringify(v)+"\\n");\n'
                ' pi.on("before_agent_start",(event:any,ctx:any)=>{\n'
                f'  const expected=readFileSync({json.dumps(str(directory/"AGENTS.md"))},"utf8").trim();\n'
                '  log({type:"prompt",session:ctx.sessionManager.getSessionId(),approvedInstructions:event.systemPrompt.includes(expected),unapprovedInstructions:event.systemPrompt.includes("PI_UNAPPROVED_FIXTURE"),tools:pi.getActiveTools(),model:ctx.model?.id,provider:ctx.model?.provider});\n'
                ' });\n'
                ' pi.on("tool_call",(event:any)=>{\n'
                '  if(event.toolName==="memory_status" && !Object.keys(event.input).length) return;\n'
                '  if(event.toolName!=="bash" || event.input.command!=="rtk git log -20") return {block:true,reason:"Not the approved synthetic test operation"};\n'
                '  log({type:"execution",command:event.input.command});\n'
                ' });\n'
                ' pi.on("agent_settled",(event:any)=>log({type:"settled",aborted:event.aborted}));\n}\n')
            pi_proxy = root/"observed-pi"
            pi_proxy.write_text(f'''#!/usr/bin/python3
import os,sys,json,hashlib
from pathlib import Path
real={shutil.which("pi")!r}
a=sys.argv[1:]
if a==["--version"]: os.execv(real,[real,*a])
extensions=[a[i+1] for i,v in enumerate(a) if v=="--extension"]
generated=[p for p in extensions if Path(p).is_relative_to(Path(extensions[0]).parent)]
Path({str(audit)!r}).write_text(json.dumps({{"arguments":a,"selected_extension_count":len(extensions),"generated_resources":[{{"path":p,"sha256":hashlib.sha256(Path(p).read_bytes()).hexdigest()}} for p in generated],"capture_denylist":'"denylist" = "denylist";' in Path(extensions[0]).read_text()}}))
i=a.index("--")
a[i:i]=["--extension",{str(observer)!r}]
os.execv(real,[real,*a])
''')
            pi_proxy.chmod(0o700)
            env = {**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
                   "GIT_PAGER": "cat", "RTK_DB_PATH": str(root/"rtk.db"), "RTK_TEE": "0",
                   "XDG_CONFIG_HOME": str(root/"config"), "XDG_DATA_HOME": str(root/"data")}
            env.pop("AI_MEMORY_CAPTURE_OWNER", None)
            failed = subprocess.run(base+model_option+["--extension", str(observer)],
                                    cwd=fixture, env=env, capture_output=True, text=True, timeout=10)
            if failed.returncode != 2 or audit.exists():
                raise AssertionError("An unselected resource override was accepted")
            passed("unselected resource flags are rejected")
            prompt = "This is a trivial integration check. Call memory_status once with an empty object. Then call bash exactly once with git log -20. Do not prefix the command with rtk. Use no other tools or commands. Briefly report the result."
            result = subprocess.run(base+model_option+["--pi-binary", str(pi_proxy), "--mode", "json", "--print", prompt], cwd=fixture, env=env,
                                    capture_output=True, text=True, timeout=180)
            if result.returncode:
                raise AssertionError("Real Pi launch did not succeed")
            records = [json.loads(line) for line in result.stdout.split("\n") if line.strip()]
            session = next(r["id"] for r in records if r.get("type") == "session")
            messages = [r["message"] for r in records if r.get("type") == "message_end"]
            if any(m.get("stopReason") in ("error", "aborted") for m in messages):
                raise AssertionError("The model request failed")
            observations = [json.loads(line) for line in observer_log.read_text().splitlines()]
            starts = [o for o in observations if o["type"] == "prompt"]
            if not starts or any(not s["approvedInstructions"] or s["unapprovedInstructions"] for s in starts):
                raise AssertionError("Instructions were not isolated correctly")
            assistant_messages = [m for m in messages if m.get("role") == "assistant"]
            if (not assistant_messages
                    or any(m.get("provider") != expected_provider or m.get("model") != expected_model for m in assistant_messages)
                    or any(s.get("provider") != expected_provider or s.get("model") != expected_model for s in starts)):
                raise AssertionError("Pi used a model other than the selected exact primary/test model")
            passed("selected exact model produced real assistant responses", model=args.model)
            passed("approved instructions reach the real Pi system prompt without project instructions")
            audit_data = json.loads(audit.read_text())
            for flag in ("--no-extensions", "--no-mcp", "--no-skills", "--no-context-files", "--no-prompt-templates", "--no-themes", "--no-approve"):
                if flag not in audit_data["arguments"]:
                    raise AssertionError("A discovery disable flag is missing")
            if sentinel.exists() or (root/"unapproved-sessions").exists() or any(not (t in ("read", "bash", "edit", "write", "ask_user_question", "quiz") or t.startswith("memory_")) for s in starts for t in s["tools"]):
                raise AssertionError("Unselected project resources were loaded")
            if (not audit_data["capture_denylist"] or len(audit_data["generated_resources"]) != 3
                    or audit_data["selected_extension_count"] != 6 or audit_data["arguments"].count("--skill") != 20):
                raise AssertionError("The approved capture/resources configuration is incorrect")
            report["generated_extension_sha256"] = [r["sha256"] for r in audit_data["generated_resources"]]
            passed("only approved resources load; project session-directory override is ignored")
            if fixture.joinpath(".ai-memory.toml").exists():
                raise AssertionError("A marker was unexpectedly created")
            status_text = memory.tool_result(messages, "memory_status")
            if fixture.name not in status_text:
                raise AssertionError("The memory tool resolved the wrong project")
            output = memory.tool_result(messages, "bash")
            executed = [o["command"] for o in observations if o["type"] == "execution"]
            if executed != ["rtk git log -20"] or len(output.encode()) >= len(raw.encode()):
                raise AssertionError("Actual rewriting/output reduction failed")
            if any(f"Launcher fixture commit {n:02d}" not in output for n in range(20)):
                raise AssertionError("A synthetic commit subject was lost")
            passed("RTK rewrites the real Pi bash tool and reduces output", raw_bytes=len(raw.encode()), reduced_bytes=len(output.encode()))
            db_path = Path.home()/".local/share/ai-memory/db/memory.sqlite"
            capture = memory.verify_capture(db_path, {"sessions": [session], "events": [{"type": "tool_call", "session": session}]})
            if capture[0]["project"] != fixture.name or capture[0]["observations_by_kind"].get("post-tool-use", 0) < 2:
                raise AssertionError("Marker-free lifecycle capture is incorrect")
            passed("marker-free projects capture both tool calls and an ended session", capture=capture)
            if not any(session in p.name for p in (agent/"sessions").rglob("*.jsonl")):
                raise AssertionError("The normal persistent Pi session was not saved")
            passed("normal persistent session is saved in the chosen agent directory")
            if any(Path(r["path"]).exists() for r in audit_data["generated_resources"]):
                raise AssertionError("Temporary generated resources were not removed")
            passed("temporary generated resources are removed after Pi exits")
            report["session"] = session
            # Exercise the actual interactive terminal path, not just print mode.
            observer_log.unlink()
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
            interactive = subprocess.Popen(base+model_option+["--pi-binary", str(pi_proxy), prompt],
                                           cwd=fixture, env={**env, "TERM": "xterm-256color"},
                                           stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            terminal_bytes = 0
            try:
                deadline = time.monotonic()+180
                settled = False
                while time.monotonic() < deadline and interactive.poll() is None:
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            terminal_bytes += len(os.read(master, 65536))
                        except OSError:
                            break
                    if observer_log.exists():
                        terminal_events = [json.loads(line) for line in observer_log.read_text().splitlines()]
                        settled = any(e["type"] == "settled" and not e["aborted"] for e in terminal_events)
                        if settled:
                            os.write(master, b"\x04")  # Pi's documented exit action on an empty editor.
                            exit_deadline = time.monotonic()+20
                            while interactive.poll() is None and time.monotonic() < exit_deadline:
                                if select.select([master], [], [], 0.1)[0]:
                                    try:
                                        terminal_bytes += len(os.read(master, 65536))
                                    except OSError:
                                        break
                            interactive.wait(timeout=1)
                            break
                if not settled or interactive.poll() != 0:
                    raise AssertionError("Interactive Pi did not settle and exit normally")
            finally:
                if interactive.poll() is None:
                    os.killpg(interactive.pid, signal.SIGTERM)
                    try:
                        interactive.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(interactive.pid, signal.SIGKILL)
                        interactive.wait(timeout=5)
                os.close(master)
            terminal_starts = [e for e in terminal_events if e["type"] == "prompt"]
            if not terminal_starts or any(not e["approvedInstructions"] or e["unapprovedInstructions"] for e in terminal_starts):
                raise AssertionError("Interactive instruction delivery failed")
            if [e["command"] for e in terminal_events if e["type"] == "execution"] != ["rtk git log -20"]:
                raise AssertionError("Interactive rewriting failed")
            if any(e.get("provider") != expected_provider or e.get("model") != expected_model for e in terminal_starts):
                raise AssertionError("Interactive Pi used a different model")
            terminal_session = terminal_starts[0]["session"]
            capture = memory.verify_capture(db_path, {"sessions": [terminal_session], "events": [{"type": "tool_call", "session": terminal_session}]})
            if capture[0]["observations_by_kind"].get("post-tool-use", 0) < 2:
                raise AssertionError("Interactive tool capture is incomplete")
            report["interactive_session"] = terminal_session
            passed("interactive terminal delivers instructions, rewrites bash, captures both tools, and exits normally", capture=capture, terminal_output_bytes=terminal_bytes)
        if memory.shared_settings_stamp() != before or stamps() != shared_before:
            raise AssertionError("Shared configuration metadata changed")
        passed("shared Pi settings, OpenCode configuration, and original instructions are unchanged")
        # Authentication status only: never print, read, or copy credential values.
        auth = subprocess.run(["pi", "auth", "check", "--provider", "openai", "--json", "--no-refresh"],
                              env={**os.environ, "PI_CODING_AGENT_DIR": str(agent)}, capture_output=True, text=True, timeout=20)
        status = json.loads(auth.stdout).get("status")
        report["primary_model_authentication"] = status
        report["primary_model_verified"] = args.model in launcher.PRIMARY_MODELS
        report["primary_model_check"] = "selected primary passed print and interactive checks" if report["primary_model_verified"] else "test model only; primary models require separate runs"
        report["complete"] = True
    except Exception as error:
        report["failure"] = {"type": type(error).__name__, "message": str(error)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    args.output.chmod(0o600)
    print("Evidence:", args.output)
    if not report["complete"]:
        print("FAIL:", report["failure"])
        raise SystemExit(1)
    print("Selected primary model verified:", report["primary_model_verified"])


if __name__ == "__main__":
    main()
