#!/usr/bin/env python3
"""Verify approved upstream ai-memory behavior through real Pi RPC sessions.

Writes synthetic fixtures to the selected store. Removes only the profile
fixture this run creates. Does not install resources or change shared config.
Credentials remain under Pi's own secure authentication mechanism.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import sqlite3
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid


class PiSession:
    def __init__(self, cwd, extension, model, events, agent_dir):
        self.events = events
        self.records = queue.Queue()
        self.command = ["pi", "--offline", "--mode", "rpc", "--no-session",
                        "--no-extensions", "--extension", str(extension), "--no-mcp",
                        "--no-skills", "--no-context-files", "--no-prompt-templates",
                        "--no-themes", "--no-approve", "--model", model,
                        "--tools", "memory_status,memory_query,memory_write_page,"
                        "memory_read_page,memory_delete_page"]
        environment = {**os.environ, "PI_CODING_AGENT_DIR": str(agent_dir)}
        self.process = subprocess.Popen(self.command, cwd=cwd, env=environment, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.state = self.request("get_state")
            self.request("set_auto_retry", enabled=False)
            # Use normal startup timing; do not hide discovery races with a delay.
            commands = self.request("get_commands").get("commands", [])
            if commands:
                raise AssertionError("Unselected skills, prompts, or commands are active")
            self.events.append({"type": "session", "id": self.state["sessionId"],
                                "model": model, "cwd": str(cwd)})
        except BaseException:
            self.close()
            raise

    def _read(self):
        for line in iter(self.process.stdout.readline, b""):
            try:
                self.records.put(json.loads(line))
            except ValueError:
                self.records.put({"type": "protocol_error"})
        self.records.put({"type": "process_exit"})

    def send(self, kind, **params):
        request_id = uuid.uuid4().hex
        self.process.stdin.write(json.dumps({"id": request_id, "type": kind, **params}).encode()+b"\n")
        self.process.stdin.flush()
        return request_id

    def receive(self, deadline):
        record = self.records.get(timeout=max(0.01, deadline-time.monotonic()))
        if record.get("type") in ("protocol_error", "process_exit"):
            raise RuntimeError("Pi protocol failed or process exited")
        if record.get("type") == "message_end":
            message = record.get("message", {})
            if message.get("role") == "assistant":
                if message.get("stopReason") in ("error", "aborted"):
                    raise RuntimeError("Pi model request failed or was aborted")
                for item in message.get("content", []):
                    if item.get("type") == "toolCall":
                        self.events.append({"type": "tool_call", "session": self.state["sessionId"],
                                            "name": item["name"], "arguments": item["arguments"]})
            elif message.get("role") == "toolResult":
                self.events.append({"type": "tool_result", "session": self.state["sessionId"],
                                    "name": message["toolName"], "is_error": message.get("isError", False)})
        return record

    def request(self, kind, **params):
        request_id = self.send(kind, **params)
        deadline = time.monotonic()+120
        while time.monotonic() < deadline:
            record = self.receive(deadline)
            if record.get("id") == request_id and record.get("type") == "response":
                if not record.get("success"):
                    raise RuntimeError(f"Pi RPC {kind} failed")
                return record.get("data", {})
        raise TimeoutError(f"Pi RPC {kind} timed out")

    def prompt(self, text):
        self.request("prompt", message=text)
        deadline = time.monotonic()+120
        while time.monotonic() < deadline:
            record = self.receive(deadline)
            if record.get("type") == "agent_settled":
                return self.request("get_messages")["messages"]
        raise TimeoutError("Pi agent did not settle")

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.close()
                self.process.wait(timeout=15)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                self.process.wait(timeout=5)


def text(message):
    content = message.get("content", "")
    if isinstance(content, str):
        return content
    return "\n".join(item.get("text", "") for item in content if item.get("type") == "text")


def tool_result(messages, name):
    results = [m for m in messages if m.get("role") == "toolResult" and m.get("toolName") == name]
    if not results or results[-1].get("isError"):
        raise AssertionError(f"No successful {name} result")
    return text(results[-1])


def unscoped_calls(messages, name):
    calls = [item for m in messages if m.get("role") == "assistant"
             for item in m.get("content", []) if item.get("type") == "toolCall" and item.get("name") == name]
    if not calls or any(any(item["arguments"].get(k) for k in ("workspace", "project", "scopes")) for item in calls):
        raise AssertionError(f"Expected unscoped {name} calls")


def shared_settings_stamp():
    path = Path.home()/".pi/agent/settings.json"
    try:
        metadata = path.stat()
        return (metadata.st_ino, metadata.st_mtime_ns, metadata.st_size)
    except FileNotFoundError:
        return None


def stored_identifiers(db_path):
    with sqlite3.connect(db_path.as_uri()+"?mode=ro", uri=True) as db:
        return {table: {row[0] for row in db.execute(f'SELECT id FROM "{table}"')}
                for table in ("pages", "sessions", "observations")}


def verify_capture(db_path, report):
    sessions = []
    with sqlite3.connect(db_path.as_uri()+"?mode=ro", uri=True) as db:
        for session_id in report["sessions"]:
            key = uuid.UUID(session_id).bytes
            row = db.execute('SELECT s.agent_kind,s.ended_at,p.name,w.name FROM sessions s '
                             'JOIN projects p ON s.project_id=p.id '
                             'JOIN workspaces w ON s.workspace_id=w.id WHERE s.id=?', (key,)).fetchone()
            if not row or row[0] != "pi" or row[1] is None:
                raise AssertionError("Captured Pi session is missing or not ended")
            kinds = dict(db.execute('SELECT kind,count(*) FROM observations '
                                    'WHERE session_id=? GROUP BY kind', (key,)))
            required = {"session-start", "session-end", "user-prompt", "stop"}
            if any(e["type"] == "tool_call" and e.get("session") == session_id for e in report["events"]):
                required |= {"pre-tool-use", "post-tool-use"}
            if not required <= kinds.keys():
                raise AssertionError("Required lifecycle observations are missing")
            scopes = list(db.execute('SELECT DISTINCT p.name FROM observations o '
                                     'JOIN projects p ON o.project_id=p.id WHERE o.session_id=?', (key,)))
            if scopes != [(row[2],)]:
                raise AssertionError("Stored observations crossed project scopes")
            sessions.append({"session": session_id, "agent": row[0], "ended": True,
                             "workspace": row[3], "project": row[2], "observations_by_kind": kinds})
    return sessions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True, help="Approved ai-memory 2.6.2 binary")
    parser.add_argument("--endpoint", required=True, help="Approved local temporary server")
    parser.add_argument("--output", type=Path, required=True, help="Sanitized evidence JSON")
    parser.add_argument("--agent-dir", type=Path, required=True,
                        help="Separate Pi test directory; authenticate through Pi /login")
    parser.add_argument("--model", action="append",
                        help="Approved test model; repeat for two models. Does not select port defaults.")
    args = parser.parse_args()
    models = args.model or ["openai/gpt-6.1-sol", "openai/gpt-6-luna"]
    if len(models) > 2:
        parser.error("Select one or two verification models")
    args.agent_dir = args.agent_dir.expanduser().resolve()
    if args.agent_dir == (Path.home()/".pi/agent").resolve():
        parser.error("Do not use the shared Pi agent directory for tests")
    if not args.agent_dir.is_dir():
        parser.error("Create and authenticate the separate Pi test directory first")
    if not args.endpoint.startswith("http://127.0.0.1:"):
        parser.error("This check requires the approved loopback server")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(args.endpoint+"/admin/status", timeout=5) as response:
        status = json.load(response)
    if status["version"] != "2.6.2":
        raise SystemExit("Expected ai-memory 2.6.2")
    db_path = Path(status["db_path"]).resolve()
    expected_db = (Path.home()/".local/share/ai-memory/db/memory.sqlite").resolve()
    if db_path != expected_db:
        raise SystemExit("Endpoint does not serve the approved existing store")
    identifiers_before = stored_identifiers(db_path)
    settings_before = shared_settings_stamp()
    report = {"server_version": status["version"], "models": models, "checks": [], "events": [],
              "profile_fixture_removed": False, "complete": False}
    suffix = uuid.uuid4().hex[:10]
    workspace = f"pi-port-{suffix}"
    project_a, project_b = f"fixture-a-{suffix}", f"fixture-b-{suffix}"
    profile_path = f"tools/pi-port-{suffix}.md"
    profile_word = f"amber-copper-{suffix}"
    clients = []
    profile_created = False
    with tempfile.TemporaryDirectory(prefix="pi-memory-verification-") as temporary:
        root = Path(temporary)
        os.chmod(root, 0o700)
        config = root/"generator.toml"
        config.write_text('embedding_provider = "none"\n[profile]\nllm = false\n')
        env = {"HOME": str(Path.home()), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
        generated = subprocess.run([str(args.binary.resolve()), "--data-dir", str(root/"generator"),
                                    "--config", str(config), "install-hooks", "--agent", "pi",
                                    "--server-url", args.endpoint, "--capture-mode", "allowlist",
                                    "--project-strategy", "repo-root"], env=env, capture_output=True,
                                   text=True, timeout=20, check=True)
        if "const TOKEN: string | null = null;" not in generated.stdout:
            raise RuntimeError("Unexpected authentication configuration in generated extension")
        extension = root/"ai-memory-pi.ts"
        extension.write_text(generated.stdout)
        report["extension_sha256"] = hashlib.sha256(generated.stdout.encode()).hexdigest()
        directories = []
        for name in (project_a, project_b):
            directory = root/name
            directory.mkdir()
            (directory/".ai-memory.toml").write_text(f'workspace = "{workspace}"\nproject = "{name}"\n')
            directories.append(directory)
        report.update(workspace=workspace, project_a=project_a, project_b=project_b)

        def start(index, model=None):
            model = model or models[0]
            client = PiSession(directories[index], extension, model, report["events"], args.agent_dir)
            clients.append(client)
            return client

        def passed(name, **evidence):
            report["checks"].append({"name": name, "passed": True, **evidence})
            print("PASS:", name, flush=True)

        try:
            # Two live processes: A must not inherit B's latest project pointer.
            a = start(0)
            b = start(1, models[-1])
            for client, expected in ((a, project_a), (b, project_b), (a, project_a)):
                messages = client.prompt("Call memory_status once without explicit scope. Do nothing else.")
                unscoped_calls(messages, "memory_status")
                result = tool_result(messages, "memory_status")
                if expected not in result or workspace not in result:
                    raise AssertionError("Concurrent session resolved to the wrong project")
            passed("concurrent session-aware routing", sessions=[a.state["sessionId"], b.state["sessionId"]])
            passed("selected models perform real memory-tool calls", models=models)

            messages = a.prompt('Write one synthetic fixture page at notes/typescript-tool.md. '
                                'Use memory_write_page with no workspace or project. Body: '
                                '# Cedar Sieve\n\nCedar Sieve is a tiny TypeScript tool built here '
                                'to remove duplicate import declarations. It emits a sorted import list. '
                                'This is synthetic test data, not a real project fact. Do nothing else.')
            tool_result(messages, "memory_write_page")
            unscoped_calls(messages, "memory_write_page")
            passed("unscoped project write")
            a.close()
            b.close()

            fresh_a = start(0)
            messages = fresh_a.prompt("What was the tiny TypeScript tool built here to remove duplicate import declarations? Use stored evidence; do not invent a tool.")
            result = tool_result(messages, "memory_query")
            if "Cedar Sieve" not in result:
                raise AssertionError("Fresh session did not retrieve the stored tool")
            passed("cross-session retrieval", session=fresh_a.state["sessionId"])
            fresh_a.close()

            fresh_b = start(1)
            messages = fresh_b.prompt(f'What was that tiny TypeScript tool built in project {project_a} '
                                     'to remove duplicate import declarations? I think this new problem '
                                     'could use it. Use stored evidence; do not invent an answer.')
            result = tool_result(messages, "memory_query")
            if "Cedar Sieve" not in result or not any("Cedar Sieve" in text(m) for m in messages if m.get("role") == "assistant"):
                raise AssertionError("Natural-language cross-project recall failed")
            passed("natural-language cross-project retrieval", session=fresh_b.state["sessionId"])

            messages = fresh_b.prompt(f'Create one temporary synthetic profile fixture with memory_write_page, '
                                     f'scope profile and path {profile_path}. Body: # Pi verification label\n\n'
                                     f'For synthetic Pi port verification fixtures only, use the label {profile_word}. '
                                     'This entry will be deleted after the delivery check. Do nothing else.')
            tool_result(messages, "memory_write_page")
            profile_created = True
            fresh_b.close()
            profile_client = start(0)
            messages = profile_client.prompt('Without calling tools, repeat any synthetic Pi verification label '
                                             'already delivered in your startup context. If none was delivered, say NONE.')
            injected = [text(m) for m in messages if m.get("customType") == "ai-memory-handoff"]
            if not injected or not any(profile_word in value and "profile" in value.lower() for value in injected):
                raise AssertionError("Profile digest was not injected through the upstream Pi extension")
            if not any(profile_word in text(m) for m in messages if m.get("role") == "assistant"):
                raise AssertionError("Pi did not see the injected profile entry")
            passed("automatic cross-project profile delivery", session=profile_client.state["sessionId"],
                   delivery="upstream ai-memory-handoff custom message", profile_path=profile_path)
        except Exception as error:
            report["failure"] = {"type": type(error).__name__, "message": str(error)}
        finally:
            if profile_created:
                try:
                    cleanup = start(1)
                    messages = cleanup.prompt(f'Delete only the temporary synthetic profile entry created by this '
                                              f'test run: call memory_delete_page with scope profile and path '
                                              f'{profile_path}. Do not delete any other page or record.')
                    tool_result(messages, "memory_delete_page")
                    report["profile_fixture_removed"] = True
                except Exception as error:
                    report["cleanup_failure"] = type(error).__name__
            for client in clients:
                client.close()
        report["sessions"] = [client.state["sessionId"] for client in clients]
        try:
            captures = verify_capture(db_path, report)
            passed("automatic lifecycle capture and isolated stored observation scopes", sessions=captures)
            identifiers_after = stored_identifiers(db_path)
            if not all(identifiers_before[t] <= identifiers_after[t] for t in identifiers_before):
                raise AssertionError("Records present before the test were removed")
            passed("pre-existing record identifiers preserved",
                   counts_before={t: len(v) for t,v in identifiers_before.items()},
                   counts_after={t: len(v) for t,v in identifiers_after.items()})
            if shared_settings_stamp() != settings_before:
                raise AssertionError("Shared Pi settings metadata changed during the test")
            passed("shared Pi settings metadata unchanged")
            if profile_created and report["profile_fixture_removed"]:
                with sqlite3.connect(db_path.as_uri()+"?mode=ro", uri=True) as db:
                    remaining = db.execute('SELECT count(*) FROM pages WHERE path=? AND is_latest=1',
                                           ("profile/"+profile_path,)).fetchone()[0]
                if remaining:
                    raise AssertionError("Synthetic profile page is still active")
        except Exception as error:
            report["capture_or_preservation_failure"] = {"type": type(error).__name__, "message": str(error)}
    report["complete"] = "capture_or_preservation_failure" not in report and "failure" not in report and (not profile_created or report["profile_fixture_removed"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    os.chmod(args.output, 0o600)
    print("Evidence:", args.output)
    if not report["complete"]:
        print("FAIL:", report.get("failure", report.get("capture_or_preservation_failure", {"type": "cleanup failure"})))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
