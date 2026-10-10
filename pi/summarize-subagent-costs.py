#!/usr/bin/env python3
"""Sum reported model usage for retained synthetic runs, without raw errors.

Catalog USD estimates are not bills. Older root observer records without a
session ID are not attributed by guessing from timestamps.
"""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runs = {str((p.resolve()/"fixture")): {"run": str(p), "sessions": [], "observers": []} for p in args.run_dir}
    roots = {}
    for file in (args.agent_dir/"sessions").glob("*.jsonl"):
        with file.open() as stream:
            header = json.loads(stream.readline())
            if header.get("cwd") not in runs:
                continue
            entries = [json.loads(line) for line in stream if line.strip()]
        target = runs[header["cwd"]]
        ownership = next((e.get("data", {}) for e in entries if e.get("customType") == "pi-subagent:thread:v1"), None)
        messages = [e for e in entries if e.get("type") in ("message", "custom_message")]
        if ownership:
            messages = messages[ownership.get("inheritedCount", 0):]
        else:
            roots[header["id"]] = target
        assistant = [e["message"] for e in messages if e.get("type") == "message" and e.get("message", {}).get("role") == "assistant"]
        usd = sum(m.get("usage", {}).get("cost", {}).get("total", 0) for m in assistant)
        name = next((e.get("name") for e in entries if e.get("type") == "session_info"), "main")
        target["sessions"].append({"id": header["id"], "name": name, "assistant_messages": len(assistant),
            "reported_tokens": sum(m.get("usage", {}).get("totalTokens", 0) for m in assistant),
            "catalog_usd": usd, "provider_models": sorted({m.get("provider", "?")+"/"+m.get("model", "?") for m in assistant})})
    root_requests = args.agent_dir/"you-should-know/requests.jsonl"
    if root_requests.exists():
        for line in root_requests.read_text().splitlines():
            e = json.loads(line)
            if e.get("sessionId") in roots:
                roots[e["sessionId"]]["observers"].append({"scope": "main", "model": e["provider"]+"/"+e["model"],
                    "thinking": e.get("thinking"), "catalog_usd": e.get("usage", {}).get("cost", {}).get("total", 0)})
    for sid, target in roots.items():
        folder = args.agent_dir/"sessions/artifacts"/sid/"child-observers"
        for child in folder.glob("*"):
            file = child/"requests.jsonl"
            if file.exists():
                entries = [json.loads(line) for line in file.read_text().splitlines() if line.strip()]
            else:
                file = child/"checks.jsonl"
                entries = [json.loads(line) for line in file.read_text().splitlines() if line.strip()] if file.exists() else []
                entries = [e for e in entries if e.get("event") == "request"]
            for e in entries:
                target["observers"].append({"scope": "child", "model": e["provider"]+"/"+e["model"],
                    "thinking": e.get("thinking"), "catalog_usd": e.get("usage", {}).get("cost", {}).get("total", 0)})
    report = {"estimates_not_bills": True,
        "limitations": ["Only reported usage is counted; unsuccessful requests with absent usage cannot be priced.",
                        "Legacy root observer records without session IDs are excluded, not guessed.",
                        "Subscription limits, retrieval charges and actual invoices are not measured."], "runs": list(runs.values())}
    for run in report["runs"]:
        run["session_catalog_usd"] = sum(e["catalog_usd"] for e in run["sessions"])
        run["observer_catalog_usd"] = sum(e["catalog_usd"] for e in run["observers"])
        run["reported_catalog_usd"] = run["session_catalog_usd"]+run["observer_catalog_usd"]
    report["reported_catalog_usd"] = sum(r["reported_catalog_usd"] for r in report["runs"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    print("Reported catalog USD estimate:", round(report["reported_catalog_usd"], 6))
    for run in report["runs"]:
        print(run["run"], round(run["reported_catalog_usd"], 6))


if __name__ == "__main__":
    main()
