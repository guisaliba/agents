#!/usr/bin/env python3
"""Live automatic delegation through the approved launcher; synthetic files only.

Retain fixtures, sanitized assignments/usage, and checks. Never retain raw
provider errors or inspect authentication. This is not an OS sandbox.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import queue
import sys
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("resource_helpers", HERE/"verify-resources.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


class LiveSession(helpers.Session):
    def receive(self, deadline):
        record = super().receive(deadline)
        if record.get("type") == "extension_ui_request" and record.get("method") in ("confirm", "select", "input"):
            raise AssertionError("The fully specified automatic test unexpectedly needs user input")
        return record

    def run(self, prompt, seconds=600):
        self.send("prompt", message=prompt)
        deadline = time.monotonic()+seconds
        settled = False
        while time.monotonic() < deadline:
            record = self.receive(deadline)
            if record.get("type") == "agent_settled":
                settled = True
                break
        if not settled:
            raise TimeoutError("Main agent did not settle")
        return self.request("get_messages")["messages"]


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
    (work/"contract.md").write_text("# Fixture contract\nAdd a Python clamp(value, low, high) function.\nReject low > high with ValueError. Return low/high for values outside the interval.\nNo dependencies, network, credentials, commits, or changes outside this fixture.\n")
    (work/"fixture.json").write_text('{"label":"AUTOMATIC-TEAM-TEST","items":[2,3,5]}\n')
    command = [sys.executable, "-B", str(HERE/"launch.py"), "--no-context-files", "--agent-dir", str(args.agent_dir.resolve()),
               "--memory-binary", str(args.memory_binary.resolve()), "--memory-endpoint", args.memory_endpoint,
               "--model", "openai/gpt-6.1-sol", "--subagents", "--ysk-model", "openai/gpt-6-luna", "--mode", "rpc"]
    report = {"complete": False, "port_complete": False, "automatic_delegation": True, "checks": [], "threads": []}
    before = helpers.memory.shared_settings_stamp()
    session = None
    try:
        session = LiveSession(command, work)
        session.request("set_auto_retry", enabled=False)
        report["root_session_id"] = session.state["sessionId"]
        prompt = (
            "Complete this synthetic project with your available specialist team. Decide when and how to delegate automatically; "
            "do not ask the user to approve starts or choose anything. No credentials, dotenv files, environment dumps, network, "
            "installs, commits, or changes outside this fixture and visual-tool staging. Read contract.md. "
            "The independent deliverables are: an architecture/acceptance plan in plan.md; a source-backed local brief in research.md "
            "about the contract and fixture.json; a small clamp.py implementation plus focused tests; a reviewer report in review.md "
            "after the implementation; a quick exact extraction of fixture.json's label and integer sum in extracted.json; "
            "and user documentation in README.md after the source is ready. Use all six bundled roles for their matching work "
            "so we can verify the approved assignments, but choose paths, timing, and tool calls yourself. Give each worker owned "
            "files and explicit authorization to write its named deliverable; review must report, not repair. "
            "Have the coder also produce one simple SVG number-line picture in viz/ with the visual tools, inspect its rendered image, "
            "and describe what it saw. Collect all results and verify the files before giving your final response. "
            "Keep work bounded; no extra features."
        )
        messages = session.run(prompt)
        # Async completion can start further turns. Ask for collection only after the first run settles.
        for _ in range(8):
            if all((work/n).exists() for n in ("plan.md", "research.md", "clamp.py", "review.md", "extracted.json", "README.md")):
                break
            messages = session.run("Collect the outstanding team results and finish the specified fixture deliverables. Do not expand scope.")
        calls = [c for m in messages if m.get("role") == "assistant" for c in m.get("content", []) if c.get("type") == "toolCall"]
        spawns = [c["arguments"] for c in calls if c.get("name") == "agent_spawn"]
        if {s.get("type") for s in spawns} != {"architect", "coder", "researcher", "reviewer", "tasker", "writer"}:
            raise AssertionError("Main agent did not automatically start all six approved roles")
        report["checks"].append({"name": "six roles automatically delegated", "passed": True})
        for name in ("plan.md", "research.md", "clamp.py", "review.md", "extracted.json", "README.md"):
            if not (work/name).is_file() or not (work/name).stat().st_size:
                raise AssertionError("A required fixture artifact is absent: "+name)
        extracted = json.loads((work/"extracted.json").read_text())
        if "AUTOMATIC-TEAM-TEST" not in str(extracted) or 10 not in extracted.values():
            raise AssertionError("Tasker extraction is incorrect")
        if not list((work/"viz").glob("*.png")):
            raise AssertionError("Coder did not publish a rendered image")
        report["checks"].append({"name": "owned deliverables and rendered image exist", "passed": True})
        expected = json.loads((HERE/"subagent-config.json").read_text())["agents"]
        session_dir = args.agent_dir.resolve()/"sessions"
        for file in session_dir.glob("*.jsonl"):
            # Only this fixture's transcripts, not unrelated user sessions.
            with file.open() as stream:
                header = json.loads(stream.readline())
                if header.get("cwd") != str(work):
                    continue
                entries = [json.loads(line) for line in stream if line.strip()]
            info = next((e.get("name", "") for e in entries if e.get("type") == "session_info"), "")
            role = info.split(" ")[0]
            if role not in expected:
                continue
            responses = [e["message"] for e in entries if e.get("type") == "message" and e.get("message", {}).get("role") == "assistant"]
            own = next((e.get("data", {}).get("inheritedCount", 0) for e in entries if e.get("customType") == "pi-subagent:thread:v1"), 0)
            # Inherited context can include other roles' responses. Ownership is recorded before it.
            all_messages = [e for e in entries if e.get("type") in ("message", "custom_message")]
            own_responses = [e["message"] for e in all_messages[own:] if e.get("type") == "message" and e.get("message", {}).get("role") == "assistant"]
            wanted = expected[role]["models"][0]
            if not own_responses or any(m.get("provider")+"/"+m.get("model") != wanted for m in own_responses):
                raise AssertionError("A child did not use its assigned model: "+role)
            thinking = [e.get("thinkingLevel") for e in entries if e.get("type") == "thinking_level_change"]
            if not thinking or thinking[-1] != expected[role]["thinkingLevel"]:
                raise AssertionError("A child did not use its assigned thinking level: "+role)
            report["threads"].append({"role": role, "session_file": str(file), "model": wanted,
                "thinking": thinking[-1], "assistant_requests": len(own_responses),
                "usage": [m.get("usage", {}) for m in own_responses]})
        if {t["role"] for t in report["threads"]} != set(expected):
            raise AssertionError("Missing assigned child transcripts")
        report["checks"].append({"name": "actual child models and thinking verified", "passed": True})
        report["main_usage"] = [m.get("usage", {}) for m in messages if m.get("role") == "assistant"]
        report["complete"] = True
    except (AssertionError, OSError, RuntimeError, TimeoutError, queue.Empty, ValueError) as error:
        report["failure"] = str(error) if isinstance(error, AssertionError) else type(error).__name__
        print("FAIL:", report["failure"], flush=True)
    finally:
        if session:
            session.close()
        report["shared_settings_metadata_unchanged"] = helpers.memory.shared_settings_stamp() == before
        if not report["shared_settings_metadata_unchanged"]:
            report["complete"] = False
        (root/"result.json").write_text(json.dumps(report, indent=2)+"\n")
    if report["complete"]:
        print("PASS: automatic team, artifacts, assigned models and thinking", flush=True)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
