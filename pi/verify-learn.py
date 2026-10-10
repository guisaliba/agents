#!/usr/bin/env python3
"""Check Learn's public Markdown commands through real, isolated Pi RPC.

Uses synthetic notes only. Does not install resources or use private notes.
Retains before/after files beside the sanitized evidence JSON.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import subprocess
import threading


def load_memory_helpers():
    path = Path(__file__).with_name("verify-ai-memory.py")
    spec = importlib.util.spec_from_file_location("memory_helpers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


memory = load_memory_helpers()


class LearnSession(memory.PiSession):
    def __init__(self, cwd, extension, model, agent_dir):
        self.events = []
        self.notifications = []
        self.records = queue.Queue()
        self.command = ["pi", "--offline", "--mode", "rpc", "--no-session",
                        "--no-extensions", "--extension", str(extension), "--no-mcp",
                        "--no-skills", "--no-context-files", "--no-prompt-templates",
                        "--no-themes", "--no-approve", "--no-tools", "--model", model]
        env = {**os.environ, "PI_CODING_AGENT_DIR": str(agent_dir)}
        self.process = subprocess.Popen(self.command, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, umask=0o077)
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.state = self.request("get_state")
            self.request("set_auto_retry", enabled=False)
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
    parser.add_argument("--extension", type=Path, required=True)
    parser.add_argument("--model", choices=("openai/gpt-6.1-sol", "openai/gpt-6-luna",
                                            "opencode-go/deepseek-v4.1-flash"),
                        default="openai/gpt-6-luna")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    agent = args.agent_dir.expanduser().resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use a separately authenticated Pi test directory")
    extension = args.extension.resolve()
    if not extension.is_file():
        parser.error("The inspected logger extension is missing")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    fixture = output.parent/(output.stem+"-fixtures")
    fixture.mkdir(mode=0o700, exist_ok=False)
    before_stamp = memory.shared_settings_stamp()
    report = {"checks": [], "complete": False, "port_complete": False,
              "scope": "real Pi Markdown command and file preservation; no subagents or visuals",
              "model": args.model, "extension_sha256": hashlib.sha256(extension.read_bytes()).hexdigest(),
              "artifacts": []}
    session = None

    def passed(name):
        report["checks"].append({"name": name, "passed": True})
        print("PASS:", name, flush=True)

    try:
        if subprocess.check_output(["pi", "--version"], text=True).strip() != "1.1.0":
            raise AssertionError("Expected Pi 1.1.0")
        note = fixture/"synthetic-note.md"
        original = "# Existing synthetic note\n\nKeep this paragraph exactly.\n\nUnicode fixture: café Δ.\r\n"
        note.write_text(original)
        note.chmod(0o600)
        (fixture/"before.md").write_text(original)
        session = LearnSession(fixture, extension, args.model, agent)
        commands = session.request("get_commands").get("commands", [])
        names = {c["name"] for c in commands}
        if names != {"md-log", "md-unlog"}:
            raise AssertionError("Unexpected command discovery")
        passed("only original Learn Markdown commands load")
        initial = fixture/"initial-read-only.md"
        initial_text = "Keep this note before any lesson starts.\n"
        initial.write_text(initial_text)
        initial.chmod(0o400)
        count = len(session.notifications)
        session.request("prompt", message=f"/md-log {initial}")
        if (initial.read_bytes().decode("utf-8") != initial_text
                or not any(n.get("notifyType") == "error" for n in session.notifications[count:])):
            raise AssertionError("Linking before the first lesson did not refuse a read-only note")
        passed("read-only linking is refused before any lesson history exists")
        encoded = fixture/"unsupported-encoding.md"
        encoded_bytes = b"Keep these original bytes.\xff\n"
        encoded.write_bytes(encoded_bytes)
        count = len(session.notifications)
        session.request("prompt", message=f"/md-log {encoded}")
        if (encoded.read_bytes() != encoded_bytes
                or not any(n.get("notifyType") == "error" for n in session.notifications[count:])):
            raise AssertionError("A note with invalid UTF-8 was changed or reported as linked")
        passed("unsupported note encoding is refused without changing its bytes")
        marker = "LEARN_SYNTHETIC_LESSON_REPLY"
        messages = session.prompt(f"Reply with only {marker}. Do not use tools.")
        provider, model = args.model.split("/", 1)
        assistants = [m for m in messages if m.get("role") == "assistant"]
        if (not assistants or any(m.get("provider") != provider or m.get("model") != model for m in assistants)
                or not any(marker in memory.text(m) for m in assistants)):
            raise AssertionError("The selected model did not produce the synthetic lesson")
        passed("selected exact model produces a real assistant response")
        report["session"] = session.state["sessionId"]
        session.request("prompt", message=f"/md-log {note}")
        after = note.read_bytes().decode("utf-8")
        (fixture/"after.md").write_text(after)
        report["artifacts"] = ["before.md", "after.md"]
        if not after.startswith(original):
            raise AssertionError("Existing note content was removed by /md-log")
        if marker not in after or "> [!abstract] PI" not in after:
            raise AssertionError("Session history was not backfilled")
        passed("linking preserves existing note content and records session history")
        suffix = "\n# Later synthetic notes\nKeep this suffix exactly.\n"
        note.write_text(after+suffix)
        session.request("prompt", message=f"/md-log {note}")
        relinked = note.read_bytes().decode("utf-8")
        (fixture/"relinked.md").write_text(relinked)
        report["artifacts"].append("relinked.md")
        if (not relinked.startswith(original) or not relinked.endswith(suffix)
                or relinked.count(marker) != after.count(marker)):
            raise AssertionError("Relinking changed unrelated notes or duplicated session history")
        passed("relinking preserves prefix and suffix without duplicate history")
        live = "LEARN_SYNTHETIC_LIVE_REPLY"
        session.prompt(f"Reply with only {live}. Do not use tools.")
        logged = note.read_bytes().decode("utf-8")
        (fixture/"live.md").write_text(logged)
        report["artifacts"].append("live.md")
        if not logged.startswith(original) or not logged.endswith(suffix) or live not in logged:
            raise AssertionError("Live logging changed unrelated text or missed the response")
        passed("live logging updates only its session section")
        session.request("new_session")
        session.state = session.request("get_state")
        session.prompt("Reply with only LEARN_NEW_UNLINKED_SESSION. Do not use tools.")
        if note.read_bytes().decode("utf-8") != logged:
            raise AssertionError("A new unlinked session wrote into the previous session's note")
        passed("a new session does not retain the previous note link")
        broken = fixture/"broken-markers.md"
        broken_text = f"Keep this damaged synthetic note.\n<!-- pi-md-log:{session.state['sessionId']}:start -->\n"
        broken.write_text(broken_text)
        count = len(session.notifications)
        session.request("prompt", message=f"/md-log {broken}")
        notifications = session.notifications[count:]
        if (broken.read_bytes().decode("utf-8") != broken_text
                or not any(n.get("notifyType") == "error" for n in notifications)
                or any(n.get("notifyType") == "success" for n in notifications)):
            raise AssertionError("Damaged markers were not refused with an honest error")
        passed("damaged section markers preserve the note and report an error")
        if os.geteuid() == 0:
            raise AssertionError("Read-only file protection must be tested as a non-root user")
        protected = fixture/"read-only.md"
        protected_text = "Keep this protected synthetic note exactly.\n"
        protected.write_text(protected_text)
        protected.chmod(0o400)
        count = len(session.notifications)
        session.request("prompt", message=f"/md-log {protected}")
        notices = session.notifications[count:]
        if (protected.read_bytes().decode("utf-8") != protected_text
                or not any(n.get("notifyType") == "error" for n in notices)
                or any(n.get("notifyType") == "success" for n in notices)):
            raise AssertionError("Read-only note protection was bypassed or a false success was reported")
        passed("read-only notes remain unchanged and linking reports an error")
        if note.stat().st_mode & 0o777 != 0o600:
            raise AssertionError("The existing note's private permission bits changed")
        passed("private note permission bits are preserved")
        readable = fixture/"readable-note.md"
        readable.write_text("Keep the existing readable note.\n")
        readable.chmod(0o644)
        session.request("prompt", message=f"/md-log {readable}")
        if readable.stat().st_mode & 0o777 != 0o644:
            raise AssertionError("The process umask changed the existing note's permission bits")
        passed("existing permission bits are retained under a restrictive process umask")
        report["complete"] = True
    except (AssertionError, OSError, RuntimeError, TimeoutError, queue.Empty) as error:
        report["failure"] = str(error) if isinstance(error, AssertionError) else type(error).__name__
        report["checks"].append({"name": "Markdown preservation", "passed": False})
        print("FAIL:", report["failure"], flush=True)
    finally:
        if session:
            session.close()
        unchanged = memory.shared_settings_stamp() == before_stamp
        report["shared_settings_metadata_unchanged"] = unchanged
        if not unchanged:
            report["complete"] = False
        report["fixture_directory"] = str(fixture)
        output.write_text(json.dumps(report, indent=2)+"\n")
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
