#!/usr/bin/env python3

"""Verify the RTK plugin with a real OpenCode V2 shell-tool run."""

import hashlib
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path


COMMAND = "git status --short --branch"
EXPECTED_OUTPUT = "RTK_SMOKE_COMPLETE"
PINNED_SHA256 = "601875c939db05c58d86d7be788f9c329c9de490faf09f30c97703cc271d4339"
REPO_ROOT = Path(__file__).resolve().parents[2]
PLUGIN_SOURCE = REPO_ROOT / "plugins" / "rtk" / "rtk.ts"


def fail(message):
    raise RuntimeError(message)


def stable_version(text, name):
    match = re.search(r"(?<!\d)v?(\d+)\.(\d+)\.(\d+)(?![A-Za-z0-9.+-])", text)
    if not match:
        fail(f"{name} did not report a stable semantic version: {text.strip()!r}")
    return tuple(map(int, match.groups()))


class ProviderState:
    def __init__(self):
        self.requests = []
        self.errors = []
        self.tool_name = None
        self.lock = threading.Lock()


class ProviderHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def send_json(self, value, status=200):
        content = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def send_stream(self, values):
        content = b"".join(
            b"data: " + json.dumps(value, separators=(",", ":")).encode() + b"\n\n"
            for value in values
        ) + b"data: [DONE]\n\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.path.endswith("/models"):
            self.send_json({
                "object": "list",
                "data": [{"id": "rtk-smoke", "object": "model", "created": 0, "owned_by": "local"}],
            })
            return
        self.send_json({"error": {"message": "unknown smoke-test endpoint"}}, 404)

    def do_POST(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(size))
            state = self.server.state
            with state.lock:
                state.requests.append(request)

            messages = request.get("messages", [])
            if any(message.get("role") in {"tool", "function"} for message in messages):
                self.respond_final(request)
                return

            if not request.get("tools"):
                self.respond_text(request, "RTK smoke test")
                return

            tool_name = None
            for tool in request.get("tools", []):
                function = tool.get("function", {})
                candidate = function.get("name") or tool.get("name")
                if isinstance(candidate, str) and candidate.lower() in {"bash", "shell"}:
                    tool_name = candidate
                    break
            if tool_name is None:
                available = [
                    item.get("function", {}).get("name") or item.get("name")
                    for item in request.get("tools", [])
                ]
                fail(f"OpenCode did not offer a bash or shell tool: {available!r}")

            state.tool_name = tool_name
            self.respond_tool(request, tool_name)
        except Exception as error:
            self.server.state.errors.append(str(error))
            self.send_json({"error": {"message": str(error)}}, 500)

    def response_base(self, request, choice):
        return {
            "id": "chatcmpl-rtk-smoke",
            "object": "chat.completion",
            "created": 0,
            "model": request.get("model", "rtk-smoke"),
            "choices": [choice],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
        }

    def respond_tool(self, request, tool_name):
        arguments = json.dumps({"command": COMMAND}, separators=(",", ":"))
        if request.get("stream"):
            prefix = {
                "id": "chatcmpl-rtk-smoke",
                "object": "chat.completion.chunk",
                "created": 0,
                "model": request.get("model", "rtk-smoke"),
            }
            self.send_stream([
                {**prefix, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]},
                {**prefix, "choices": [{"index": 0, "delta": {"tool_calls": [{
                    "index": 0,
                    "id": "call_rtksmoke",
                    "type": "function",
                    "function": {"name": tool_name, "arguments": ""},
                }]}, "finish_reason": None}]},
                {**prefix, "choices": [{"index": 0, "delta": {"tool_calls": [{
                    "index": 0,
                    "function": {"arguments": arguments},
                }]}, "finish_reason": None}]},
                {**prefix, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]},
            ])
            return
        call = {
            "index": 0,
            "id": "call_rtksmoke",
            "type": "function",
            "function": {"name": tool_name, "arguments": arguments},
        }
        self.send_json(self.response_base(request, {
            "index": 0,
            "message": {"role": "assistant", "content": None, "tool_calls": [call]},
            "finish_reason": "tool_calls",
        }))

    def respond_final(self, request):
        self.respond_text(request, EXPECTED_OUTPUT)

    def respond_text(self, request, text):
        if request.get("stream"):
            prefix = {
                "id": "chatcmpl-rtk-smoke",
                "object": "chat.completion.chunk",
                "created": 0,
                "model": request.get("model", "rtk-smoke"),
            }
            self.send_stream([
                {**prefix, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]},
                {**prefix, "choices": [{"index": 0, "delta": {"content": text}, "finish_reason": None}]},
                {**prefix, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
            ])
            return
        self.send_json(self.response_base(request, {
            "index": 0,
            "message": {"role": "assistant", "content": text},
            "finish_reason": "stop",
        }))


def isolated_environment(home, wrapper_dir, rtk_bin, log_paths):
    env = os.environ.copy()
    for name in list(env):
        if name.startswith("OPENCODE_") or name.endswith(("_API_KEY", "_TOKEN", "_PASSWORD")):
            env.pop(name, None)

    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_STATE_HOME": str(home / ".local" / "state"),
        "RTK_BIN": str(rtk_bin),
        "RTK_REAL_BIN": str(rtk_bin),
        "RTK_SMOKE_COMMAND_LOG": str(log_paths["commands"]),
        "RTK_SMOKE_OUTPUT_LOG": str(log_paths["output"]),
        "RTK_SMOKE_API_KEY": "local-smoke-only",
        "PATH": str(wrapper_dir) + os.pathsep + env.get("PATH", os.defpath),
    })
    return env


def run_smoke():
    if os.name != "posix":
        fail("This smoke test supports macOS and Linux only")
    if not PLUGIN_SOURCE.is_file():
        fail(f"Missing tracked RTK plugin source: {PLUGIN_SOURCE}")
    source_sha256 = hashlib.sha256(PLUGIN_SOURCE.read_bytes()).hexdigest()
    if source_sha256 != PINNED_SHA256:
        fail(f"Tracked RTK plugin does not match its pinned SHA-256: {source_sha256}")

    opencode = os.environ.get("OPENCODE_BIN") or shutil.which("opencode")
    rtk_bin = os.environ.get("RTK_BIN") or shutil.which("rtk")
    if not opencode:
        fail("OpenCode is not on PATH; set OPENCODE_BIN to a stable V2 binary")
    if not rtk_bin:
        fail("RTK is not on PATH; set RTK_BIN to a compatible stable RTK binary")

    with tempfile.TemporaryDirectory(prefix="rtk-v2-smoke-") as scratch_text:
        scratch = Path(scratch_text)
        home = scratch / "home"
        workspace = scratch / "workspace"
        plugin_dir = home / ".config" / "opencode" / "plugins"
        wrapper_dir = scratch / "bin"
        plugin_target = plugin_dir / "rtk.ts"
        command_log = scratch / "executed-command.log"
        output_log = scratch / "shell-output.log"
        plugin_dir.mkdir(parents=True)
        workspace.mkdir()
        wrapper_dir.mkdir()
        shutil.copyfile(PLUGIN_SOURCE, plugin_target)
        plugin_target.chmod(0o644)

        log_paths = {"commands": command_log, "output": output_log}
        provider = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ProviderHandler)
        provider.state = ProviderState()
        provider_thread = threading.Thread(target=provider.serve_forever, daemon=True)
        provider_url = f"http://127.0.0.1:{provider.server_address[1]}/v1"
        rtk_bin = Path(rtk_bin).resolve()
        env = isolated_environment(home, wrapper_dir, rtk_bin, log_paths)
        env["PWD"] = str(workspace)

        wrapper = wrapper_dir / "rtk"
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            "printf 'rtk %s\\n' \"$*\" >>\"$RTK_SMOKE_COMMAND_LOG\"\n"
            "\"$RTK_REAL_BIN\" \"$@\" >\"$RTK_SMOKE_OUTPUT_LOG\" 2>&1\n"
            "result=$?\n"
            "cat \"$RTK_SMOKE_OUTPUT_LOG\"\n"
            "exit \"$result\"\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)

        config = {
            "$schema": "https://opencode.ai/config.json",
            "update": "disable",
            "model": "rtk-smoke/rtk-smoke",
            "providers": {
                "rtk-smoke": {
                    "name": "Local RTK smoke provider",
                    "env": ["RTK_SMOKE_API_KEY"],
                    "package": "@opencode/ai/providers/openai-compatible",
                    "settings": {"baseURL": provider_url},
                    "models": {
                        "rtk-smoke": {
                            "name": "Local RTK smoke model",
                            "capabilities": {
                                "tools": True,
                                "input": ["text"],
                                "output": ["text"],
                            },
                            "limit": {"context": 200000, "output": 32000},
                        },
                    },
                },
            },
            "permissions": [
                {"action": "shell", "resource": "*", "effect": "ask"},
                {"action": "shell", "resource": COMMAND, "effect": "allow"},
                {"action": "shell", "resource": f"rtk {COMMAND}", "effect": "allow"},
            ],
        }
        config_path = home / ".config" / "opencode" / "opencode.json"
        config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

        subprocess.run(["git", "init", "--quiet"], cwd=workspace, env=env, check=True)
        (workspace / "smoke.txt").write_text("temporary smoke fixture\n", encoding="utf-8")

        opencode_version_result = subprocess.run(
            [opencode, "--version"], cwd=workspace, env=env, text=True,
            capture_output=True, check=True, timeout=10,
        )
        opencode_version = opencode_version_result.stdout.strip()
        parsed_opencode_version = stable_version(opencode_version, "OpenCode")
        if parsed_opencode_version[0] != 2 or parsed_opencode_version < (2, 0, 18):
            fail(f"Expected stable OpenCode V2, found {opencode_version!r}")

        rtk_version_result = subprocess.run(
            [str(rtk_bin), "--version"], cwd=workspace, env=env, text=True,
            capture_output=True, check=True, timeout=10,
        )
        rtk_version = rtk_version_result.stdout.strip()
        stable_version(rtk_version, "RTK")
        rewrite = subprocess.run(
            [str(rtk_bin), "rewrite", COMMAND], cwd=workspace, env=env,
            text=True, capture_output=True, timeout=5,
        )
        rewritten = rewrite.stdout.strip()
        if rewrite.returncode not in {0, 3} or not rewritten or rewritten == COMMAND:
            fail(f"RTK rewrite check failed: exit={rewrite.returncode}, output={rewritten!r}")

        prompt = f"Run exactly this shell command once: {COMMAND}. Do not run any other command."
        provider_thread.start()
        opencode_command = [
            opencode, "run", "--standalone", "--agent", "build",
            "--model", "rtk-smoke/rtk-smoke", "--format", "json", prompt,
        ]
        if os.environ.get("RTK_SMOKE_DEBUG") == "1":
            opencode_command = [opencode, "--print-logs", "--log-level", "debug", *opencode_command[1:]]
        try:
            result = subprocess.run(
                opencode_command,
                cwd=workspace, env=env, text=True, capture_output=True, timeout=90,
            )
        finally:
            provider.shutdown()
            provider.server_close()
            provider_thread.join(timeout=5)

        if result.returncode != 0:
            request_summary = [
                {
                    "model": request.get("model"),
                    "stream": request.get("stream"),
                    "messages": [
                        {
                            "role": message.get("role"),
                            "content": str(message.get("content", ""))[:180],
                        }
                        for message in request.get("messages", [])
                    ],
                    "tools": [
                        item.get("function", {}).get("name") or item.get("name")
                        for item in request.get("tools", [])
                    ],
                    "shell_schema": next((
                        item.get("function", {}).get("parameters")
                        for item in request.get("tools", [])
                        if (item.get("function", {}).get("name") or item.get("name")) == "shell"
                    ), None),
                }
                for request in provider.state.requests
            ]
            command_trace = command_log.read_text(encoding="utf-8") if command_log.exists() else "<no shell command>"
            shell_trace = output_log.read_text(encoding="utf-8") if output_log.exists() else "<no shell output>"
            fail(
                "OpenCode smoke run failed.\n"
                f"local provider: requests={len(provider.state.requests)}, "
                f"tool={provider.state.tool_name!r}, errors={provider.state.errors!r}\n"
                f"request summary: {request_summary!r}\n"
                f"executed command: {command_trace!r}\n"
                f"shell output: {shell_trace!r}\n"
                f"stdout:\n{result.stdout[-12000:]}\n"
                f"stderr:\n{result.stderr[-12000:]}"
            )
        if EXPECTED_OUTPUT not in result.stdout:
            fail(f"OpenCode did not return its final smoke marker: {result.stdout[-4000:]}")
        if provider.state.errors:
            fail(f"Local provider error: {provider.state.errors[0]}")
        if provider.state.tool_name is None:
            fail("The local provider did not receive a shell-tool request")
        if not command_log.is_file():
            fail("The real shell tool did not run the RTK wrapper")

        executed = command_log.read_text(encoding="utf-8").strip()
        shell_output = output_log.read_text(encoding="utf-8").strip() if output_log.exists() else ""
        if executed != rewritten:
            fail(f"RTK did not rewrite the command as expected: {executed!r} != {rewritten!r}")
        if "smoke.txt" not in shell_output:
            fail(f"The real RTK shell command did not report the fixture file: {shell_output!r}")

        report = {
            "result": "passed",
            "opencode_version": opencode_version,
            "rtk_version": rtk_version,
            "plugin_sha256": hashlib.sha256(plugin_target.read_bytes()).hexdigest(),
            "plugin_path": "~/.config/opencode/plugins/rtk.ts (isolated HOME)",
            "provider": "local OpenAI-compatible test provider; no credential used",
            "permission_authorization": {
                "shell_default": "ask",
                "allowed_commands": [COMMAND, rewritten],
                "auto_approval": False,
            },
            "tool_name": provider.state.tool_name,
            "command_before": COMMAND,
            "command_after": executed,
            "shell_output": shell_output,
            "provider_requests": len(provider.state.requests),
        }
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        run_smoke()
    except Exception as error:
        print(f"RTK OpenCode V2 smoke test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
