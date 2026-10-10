#!/usr/bin/env python3
"""Test the approved upstream RTK extension through Pi's model-called bash tool.

Uses private Git fixtures, a test-only command gate, and an RTK audit wrapper.
The wrapper delegates real rewrites/execution to the installed CLI except in
explicit helper-failure cases. None of this instrumentation is port runtime code.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

from importlib.util import module_from_spec, spec_from_file_location


# Reuse the existing read-only shared-settings metadata check, not its runner.
spec = spec_from_file_location("memory_verification", Path(__file__).with_name("verify-ai-memory.py"))
memory_verification = module_from_spec(spec)
spec.loader.exec_module(memory_verification)

GIT_COMMAND = "git log -20"
UNSUPPORTED = "printf PI_RTK_UNSUPPORTED_OK"
FAILURE = "git log --definitely-invalid-pi-test-option"


def run_case(root, extension, guard, shim_dir, agent_dir, model, mode, command,
             memory_extension=None):
    audit = root/f"{mode}-rtk.jsonl"
    executed = root/f"{mode}-executed.jsonl"
    environment = {**os.environ, "PI_CODING_AGENT_DIR": str(agent_dir),
                   "PATH": str(shim_dir)+os.pathsep+os.environ.get("PATH", "/usr/bin:/bin"),
                   "PI_RTK_AUDIT": str(audit), "PI_RTK_EXECUTED": str(executed),
                   "PI_RTK_MODE": mode, "GIT_CONFIG_GLOBAL": "/dev/null",
                   "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_PAGER": "cat",
                   "GIT_TERMINAL_PROMPT": "0"}
    environment.pop("RTK_DISABLED", None)
    if mode == "disabled":
        environment["RTK_DISABLED"] = "1"
    arguments = ["pi", "--offline", "--print", "--mode", "json", "--no-session",
                 "--no-extensions", "--no-mcp", "--no-skills", "--no-context-files",
                 "--no-prompt-templates", "--no-themes", "--no-approve", "--model", model]
    if memory_extension:
        arguments += ["--extension", str(memory_extension)]
    arguments += ["--extension", str(extension), "--extension", str(guard),
                  "--tools", "bash,memory_status" if memory_extension else "bash"]
    prompt = f"Call bash exactly once with this exact command: {command}\n"
    prompt += "Do not prefix it with rtk or change the command. Do not run any other shell command. "
    if memory_extension:
        prompt += "Then call memory_status once with no workspace or project. "
    prompt += "Report whether the requested calls succeeded; do not retry a failed command."
    result = subprocess.run(arguments+[prompt], cwd=root/"fixture", env=environment,
                            capture_output=True, text=True, timeout=120)
    records = []
    for line in result.stdout.split("\n"):
        if line.strip():
            records.append(json.loads(line))
    if result.returncode:
        raise AssertionError("Pi exited unsuccessfully")
    messages = [r.get("message", {}) for r in records if r.get("type") == "message_end"]
    if any(m.get("stopReason") in ("error", "aborted") for m in messages):
        raise AssertionError("Pi model request failed or was aborted")
    outputs = [m for m in messages if m.get("role") == "toolResult" and m.get("toolName") == "bash"]
    if len(outputs) != 1:
        raise AssertionError("Expected exactly one real bash tool result")
    calls = [json.loads(line) for line in audit.read_text().splitlines()] if audit.exists() else []
    commands = [json.loads(line) for line in executed.read_text().splitlines()] if executed.exists() else []
    if len(commands) != 1:
        raise AssertionError("Expected one executed command after RTK's handler")
    output = memory_verification.text(outputs[0])
    session_id = next((r.get("id") for r in records if r.get("type") == "session"), None)
    evidence = {"mode": mode, "requested_command": command, "executed_command": commands[0]["command"],
                "rtk_subprocess_arguments": calls, "output": output,
                "output_bytes": len(output.encode()), "tool_is_error": outputs[0].get("isError", False),
                "session": session_id}
    if memory_extension:
        status = memory_verification.tool_result(messages, "memory_status")
        if "pi-rtk-verification" not in status:
            raise AssertionError("Combined memory call resolved to the wrong project")
        evidence["memory_status_succeeded"] = True
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", default="opencode-go/deepseek-v4.1-flash")
    parser.add_argument("--memory-binary", type=Path, required=True)
    parser.add_argument("--memory-endpoint", required=True)
    args = parser.parse_args()
    agent_dir = args.agent_dir.expanduser().resolve()
    if not agent_dir.is_dir() or agent_dir == (Path.home()/".pi/agent").resolve():
        parser.error("Use the approved, separately authenticated Pi test directory")
    if not args.memory_endpoint.startswith("http://127.0.0.1:"):
        parser.error("Use the approved loopback ai-memory endpoint")
    real_rtk = shutil.which("rtk")
    if not real_rtk:
        raise SystemExit("RTK is not installed")
    version = subprocess.check_output([real_rtk, "--version"], text=True).strip()
    before = memory_verification.shared_settings_stamp()
    report = {"rtk_version": version, "model": args.model, "checks": [], "cases": [], "complete": False}
    with tempfile.TemporaryDirectory(prefix="pi-rtk-verification-") as temporary:
        root = Path(temporary)
        root.chmod(0o700)
        fixture = root/"fixture"
        fixture.mkdir()
        setup_env = {"HOME": str(root/"home"), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
                     "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
                     "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z"}
        Path(setup_env["HOME"]).mkdir()
        for command in (["git", "init", "--quiet"], ["git", "config", "user.name", "Pi Fixture"],
                        ["git", "config", "user.email", "fixture@example.invalid"]):
            subprocess.run(command, cwd=fixture, env=setup_env, check=True, capture_output=True)
        for number in range(20):
            subprocess.run(["git", "commit", "--quiet", "--allow-empty", "-m", f"Synthetic fixture commit {number:02d}"],
                           cwd=fixture, env=setup_env, check=True, capture_output=True)
        subprocess.run([real_rtk, "init", "--agent", "pi", "--no-trust-filters"], cwd=fixture,
                       env=setup_env, check=True, capture_output=True)
        extension = fixture/".pi/extensions/rtk.ts"
        report["extension_sha256"] = hashlib.sha256(extension.read_bytes()).hexdigest()
        shim_dir = root/"bin"
        shim_dir.mkdir()
        shim = shim_dir/"rtk"
        shim.write_text(f'''#!/usr/bin/python3
import json,os,sys,time
from pathlib import Path
with open(os.environ["PI_RTK_AUDIT"],"a") as log:
    log.write(json.dumps(sys.argv[1:])+"\\n")
mode=os.environ["PI_RTK_MODE"]
if sys.argv[1:]==["--version"] and mode=="missing": sys.exit(127)
if sys.argv[1:]==["--version"] and mode=="old":
    print("rtk 0.22.0");sys.exit(0)
if len(sys.argv)>1 and sys.argv[1]=="rewrite":
    if mode=="helper-error": sys.exit(1)
    if mode=="timeout":
        print("rtk git log -20",flush=True);time.sleep(6);sys.exit(0)
# Real rewriting/execution, with RTK configuration and metrics isolated.
env={{"HOME":{str(root/"home")!r},"PATH":"/usr/bin:/bin","LANG":"C.UTF-8",
     "XDG_CONFIG_HOME":{str(root/"config")!r},"XDG_DATA_HOME":{str(root/"data")!r},
     "RTK_DB_PATH":{str(root/"metrics.db")!r},"RTK_TEE":"0",
     "GIT_CONFIG_GLOBAL":"/dev/null","GIT_CONFIG_SYSTEM":"/dev/null","GIT_PAGER":"cat"}}
os.execve({real_rtk!r},[{real_rtk!r},*sys.argv[1:]],env)
''')
        shim.chmod(0o700)
        guard = root/"test-command-gate.ts"
        allowed = [GIT_COMMAND, "rtk "+GIT_COMMAND, UNSUPPORTED, FAILURE, "rtk "+FAILURE]
        guard.write_text('import { appendFileSync } from "node:fs";\n'
                         'export default function(pi: any) {\n'
                         '  pi.on("tool_call", (event: any) => {\n'
                         '    if (event.toolName === "memory_status") return;\n'
                         f'    const allowed = {json.dumps(allowed)};\n'
                         '    if (event.toolName !== "bash" || !allowed.includes(event.input.command))\n'
                         '      return { block: true, reason: "Not an approved synthetic test command" };\n'
                         '    appendFileSync(process.env.PI_RTK_EXECUTED!, JSON.stringify({command:event.input.command})+"\\n");\n'
                         '  });\n}\n')

        def case(mode, command=GIT_COMMAND, memory_extension=None):
            value = run_case(root, extension, guard, shim_dir, agent_dir, args.model, mode, command, memory_extension)
            report["cases"].append(value)
            return value

        def passed(name, **evidence):
            report["checks"].append({"name": name, "passed": True, **evidence})
            print("PASS:", name, flush=True)

        try:
            raw = case("disabled")
            if raw["executed_command"] != GIT_COMMAND or raw["tool_is_error"]:
                raise AssertionError("RTK_DISABLED did not preserve the original command")
            passed("RTK_DISABLED preserves the original command")
            compact = case("enabled")
            if compact["executed_command"] != "rtk "+GIT_COMMAND or compact["tool_is_error"]:
                raise AssertionError("Pi bash command was not rewritten")
            if ["rewrite", GIT_COMMAND] not in compact["rtk_subprocess_arguments"] or ["git", "log", "-20"] not in compact["rtk_subprocess_arguments"]:
                raise AssertionError("Real RTK rewrite and execution were not observed")
            if compact["output_bytes"] >= raw["output_bytes"]:
                raise AssertionError("RTK did not reduce model-visible output")
            for number in range(20):
                marker = f"Synthetic fixture commit {number:02d}"
                if marker not in raw["output"] or marker not in compact["output"]:
                    raise AssertionError("A fixture commit disappeared from reduced output")
            passed("actual rewriting and output reduction through Pi bash", raw_bytes=raw["output_bytes"],
                   reduced_bytes=compact["output_bytes"], reduction_percent=round(100*(1-compact["output_bytes"]/raw["output_bytes"]), 2))
            unsupported = case("unsupported", UNSUPPORTED)
            if unsupported["executed_command"] != UNSUPPORTED or unsupported["tool_is_error"] or "PI_RTK_UNSUPPORTED_OK" not in unsupported["output"]:
                raise AssertionError("Unsupported command was changed or failed")
            passed("unsupported command passes through")
            failure = case("command-error", FAILURE)
            if not failure["tool_is_error"]:
                raise AssertionError("Command failure was hidden")
            passed("command failure remains a failed Pi tool result")
            for mode in ("helper-error", "timeout", "missing", "old"):
                value = case(mode)
                if value["executed_command"] != GIT_COMMAND or value["tool_is_error"] or value["output"] != raw["output"]:
                    raise AssertionError(f"{mode} did not preserve original execution")
                passed(f"{mode} preserves original execution")
            # Verify both approved integrations together through the product path.
            config = root/"memory-generator.toml"
            config.write_text('embedding_provider = "none"\n')
            generated = subprocess.run([str(args.memory_binary.resolve()), "--data-dir", str(root/"generator"),
                                        "--config", str(config), "install-hooks", "--agent", "pi",
                                        "--server-url", args.memory_endpoint, "--capture-mode", "allowlist"],
                                       env=setup_env, capture_output=True, text=True, check=True)
            if "const TOKEN: string | null = null;" not in generated.stdout:
                raise AssertionError("Unexpected credential configuration")
            memory_extension = root/"ai-memory-pi.ts"
            memory_extension.write_text(generated.stdout)
            (fixture/".ai-memory.toml").write_text(f'workspace = "pi-rtk-verification"\nproject = "combined-{uuid.uuid4().hex[:10]}"\n')
            combined = case("combined", memory_extension=memory_extension)
            if combined["executed_command"] != "rtk "+GIT_COMMAND or combined["tool_is_error"] or not combined["memory_status_succeeded"]:
                raise AssertionError("Combined integration failed")
            if not combined["session"]:
                raise AssertionError("Combined Pi session ID missing")
            db_path = Path.home()/".local/share/ai-memory/db/memory.sqlite"
            with sqlite3.connect(db_path.as_uri()+"?mode=ro", uri=True) as db:
                session_key = uuid.UUID(combined["session"]).bytes
                ended = db.execute('SELECT ended_at FROM sessions WHERE id=?', (session_key,)).fetchone()
                observations = dict(db.execute('SELECT kind,count(*) FROM observations WHERE session_id=? GROUP BY kind', (session_key,)))
            if not ended or ended[0] is None or observations.get("post-tool-use", 0) < 2:
                raise AssertionError("Combined session capture is incomplete")
            passed("ai-memory and RTK work together", session=combined["session"], observations_by_kind=observations)
            if memory_verification.shared_settings_stamp() != before:
                raise AssertionError("Shared Pi settings metadata changed")
            passed("shared Pi settings metadata unchanged")
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


if __name__ == "__main__":
    main()
