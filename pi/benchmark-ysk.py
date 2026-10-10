#!/usr/bin/env python3
"""Run an approved paired detector pilot or corrected control-only comparison.

Uses upstream's unchanged detection prompt and equivalent tool-free side calls,
not the scheduler, UI, stored feedback, or a paid main-agent conversation.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import random
import re
import shutil
import statistics
import tempfile
import time

from resources import pinned_source

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("resource_checks", HERE/"verify-resources.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def transcript(case):
    usage = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 0,
             "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0}}
    def assistant(content, stop):
        return {"role": "assistant", "content": content, "api": "openai-responses", "provider": "openai",
                "model": "gpt-6-luna", "usage": usage, "stopReason": stop, "timestamp": 0}
    def tool(id, name, text):
        return {"role": "toolResult", "toolCallId": id, "toolName": name,
                "content": [{"type": "text", "text": text}], "isError": False, "timestamp": 0}
    path = case["evidence"].rsplit(":", 1)[0]
    user = case["user"] + ("\n\nInspection context: " + case["context"] if case.get("context") else "")
    messages = [{"role": "user", "content": user, "timestamp": 0},
            assistant([{"type": "toolCall", "id": "inspect", "name": "read", "arguments": {"path": path}}], "toolUse"),
            tool("inspect", "read", case["before"]),
            assistant([{"type": "toolCall", "id": "change", "name": "edit", "arguments": {
                "path": path, "oldText": case["before"], "newText": case["edit"]}}], "toolUse"),
            tool("change", "edit", "Edit applied. Updated content:\n" + case["edit"])]
    if case.get("verification"):
        messages += [assistant([{"type": "toolCall", "id": "verify", "name": "bash",
                                 "arguments": {"command": case["verification_command"]}}], "toolUse"),
                     tool("verify", "bash", case["verification"])]
    return messages + [assistant([{"type": "text", "text": case["assistant"]}], "stop")]


def parsed(text):
    for line in text.splitlines():
        clean = re.sub(r'^[\s>*_`"\'\u201c\u201d\u2018\u2019-]+', '', line)
        match = re.match(r"learn\s*:\s*(.*)", clean, re.I)
        if match:
            value = match.group(1).rstrip("*_` \t").strip()
            return "none" if not value or re.fullmatch(r"none\.?", value, re.I) else "note"
    return "parse_failed"


def stamp_feedback(agent):
    result = {}
    for name in ("config.json", "state.json", "knowledge.jsonl", "checks.jsonl"):
        file = agent/"you-should-know"/name
        stat = file.stat() if file.exists() else None
        result[name] = (stat.st_ino, stat.st_size, stat.st_mtime_ns) if stat else None
    return result


def run_job(job, root, agent):
    input_file = root/(job["id"]+".job.json")
    input_file.write_text(json.dumps(job, indent=2)+"\n")
    command = ["/usr/bin/env", f"PI_CODING_AGENT_DIR={agent}", f"YSK_BENCH_DIR={root}", shutil.which("pi"),
               "--offline", "--mode", "rpc", "--no-session", "--no-extensions", "--extension", str(HERE/"ysk-benchmark-driver.ts"),
               "--no-context-files", "--no-mcp", "--no-skills", "--no-prompt-templates", "--no-themes",
               "--no-approve", "--no-tools", "--model", "openai/gpt-6-luna"]
    client = None
    try:
        client = checks.Session(command, root)
        request = client.send("prompt", message=f"/ysk-benchmark {input_file}")
        deadline = time.monotonic()+330
        while time.monotonic() < deadline:
            record = client.receive(deadline)
            if record.get("id") == request and record.get("type") == "response":
                if not record.get("success"):
                    raise RuntimeError("Benchmark command failed")
                break
        else:
            raise TimeoutError()
        result = json.loads(Path(job["output"]).read_text())
        result["parsed"] = parsed(result.get("text", ""))
        result["input_sha256"] = job["input_sha256"]
        return result
    except (OSError, RuntimeError, TimeoutError, queue.Empty) as error:
        result = {"id": job["id"], "case": job["case"], "repetition": job["repetition"],
                  "requested_model": job["model"], "requested_reasoning": job["reasoning"],
                  "success": False, "error_category": type(error).__name__, "input_sha256": job["input_sha256"]}
        Path(job["output"]).write_text(json.dumps(result, indent=2)+"\n")
        return result
    finally:
        if client:
            client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--corpus", choices=("pilot", "controls"), default="pilot")
    args = parser.parse_args()
    agent = args.agent_dir.resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use the separate authenticated test directory")
    if not 1 <= args.workers <= 6:
        parser.error("Use 1 to 6 concurrent requests")
    output = args.output_dir.resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    source, pin = pinned_source(agent, "you-should-know")
    template = source/"extensions/you-should-know/detect-prompt.md"
    corpus_file = HERE/("ysk-controls.json" if args.corpus == "controls" else "ysk-corpus.json")
    corpus = json.loads(corpus_file.read_text())
    assert len(corpus["cases"]) == (6 if args.corpus == "controls" else 12)
    assert sum(c["expected"] == "note" for c in corpus["cases"]) == (0 if args.corpus == "controls" else 6)
    total = len(corpus["cases"])*3*2
    report = {"complete": False, "port_complete": False, "grading_complete": False, "requests_planned": total,
              "corpus": args.corpus, "corpus_scope": corpus["scope"],
              "workers": args.workers, "repetitions": 3, "upstream_commit": pin["commit"],
              "template_sha256": digest(template), "corpus_sha256": digest(corpus_file),
              "driver_sha256": digest(HERE/"ysk-benchmark-driver.ts"),
              "scope": "Detector prompt and side-call contract; no scheduler/UI/feedback test; no paid main calls",
              "settings": {"openai/gpt-6-luna": "max", "openai/gpt-6.1-sol": "low"}, "results": []}
    (output/"protocol.json").write_text(json.dumps(report, indent=2)+"\n")
    before = checks.memory.shared_settings_stamp()
    feedback = stamp_feedback(agent)
    started = time.monotonic()
    try:
        with tempfile.TemporaryDirectory(prefix="ysk-benchmark-jobs-") as temporary:
            root = Path(temporary)
            jobs = []
            for case in corpus["cases"]:
                messages = transcript(case)
                base = {"messages": messages, "system_prompt": corpus["system_prompt"]}
                fingerprint = hashlib.sha256(json.dumps(base, sort_keys=True).encode()).hexdigest()
                for repetition in range(1, 4):
                    for model, reasoning in report["settings"].items():
                        id = f'{case["id"]}-r{repetition}-{model.split("/")[1]}'
                        jobs.append({**base, "id": id, "case": case["id"], "repetition": repetition,
                                     "model": model, "reasoning": reasoning, "input_sha256": fingerprint,
                                     "template": str(template), "output": str(root/(id+".result.json"))})
            random.Random(20260522).shuffle(jobs)
            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                pending = {pool.submit(run_job, job, root, agent): job for job in jobs}
                for future in as_completed(pending):
                    result = future.result()
                    report["results"].append(result)
                    (output/"results.json").write_text(json.dumps(report, indent=2)+"\n")
                    print(f'{len(report["results"])}/{total} {result["id"]}: '
                          f'{result.get("parsed", result.get("error_category"))}; success={result["success"]}', flush=True)
        report["results"].sort(key=lambda r: r["id"])
        report["complete"] = len(report["results"]) == total and all(r["success"] for r in report["results"])
    finally:
        report["elapsed_seconds"] = time.monotonic()-started
        report["shared_settings_metadata_unchanged"] = before == checks.memory.shared_settings_stamp()
        report["ysk_feedback_metadata_unchanged"] = feedback == stamp_feedback(agent)
        report["complete"] &= report["shared_settings_metadata_unchanged"] and report["ysk_feedback_metadata_unchanged"]
        for model in report["settings"]:
            rows = [r for r in report["results"] if r["requested_model"] == model]
            report.setdefault("summary", {})[model] = {"requests": len(rows), "successful": sum(r["success"] for r in rows),
                "none": sum(r.get("parsed") == "none" for r in rows), "notes": sum(r.get("parsed") == "note" for r in rows),
                "catalog_cost_estimate": sum(r.get("usage", {}).get("cost", {}).get("total", 0) for r in rows),
                "median_elapsed_ms": statistics.median([r["elapsed_ms"] for r in rows if "elapsed_ms" in r]) if rows else None}
        (output/"results.json").write_text(json.dumps(report, indent=2)+"\n")
        review = ["# Model-blind detector review", "", "Model identities, reasoning, timing, and cost are withheld.",
                  "Grade the finding, its evidence, and any unsupported claim before opening results.json.", ""]
        key = []
        for case in corpus["cases"]:
            review += [f'## {case["id"]}', f'Expected: {case["expected"]}. {case["finding"]}',
                       f'User: {case["user"]}', "```", case["before"], "---", case["edit"], "```", ""]
            if case.get("context"):
                review += ["Inspection context: " + case["context"], ""]
            if case.get("verification"):
                review += ["Synthetic verification replay: " + case["verification_command"],
                           "```", case["verification"], "```", ""]
            rows = [r for r in report["results"] if r["case"] == case["id"]]
            random.Random(1000+int(case["id"][1:])).shuffle(rows)
            for index, row in enumerate(rows):
                label = f'{case["id"]}-{chr(65+index)}'
                key.append({"label": label, "id": row["id"]})
                review += [f'### {label}', row.get("text", "[Request failed; do not score as a missed finding.]"), ""]
        (output/"blind-review.md").write_text("\n".join(review))
        (output/"blind-key.json").write_text(json.dumps(key, indent=2)+"\n")
    print(json.dumps(report["summary"], indent=2), flush=True)
    print("Execution complete:", report["complete"], "; grading is pending", flush=True)
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
