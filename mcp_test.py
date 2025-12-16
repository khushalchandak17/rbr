#!/usr/bin/env python3
import sys
import json
import os
import re

# --- CONFIGURATION ---
MAX_LIST_ITEMS = 15
MAX_CHAR_LIMIT = 8000

# =====================================================
# CORE LOGIC
# =====================================================
def safe_read(filepath):
    if not os.path.exists(filepath): return None
    try:
        with open(filepath, 'r', errors='replace') as f:
            return f.read()
    except Exception: return None

def truncate_list(data):
    if len(data) > MAX_LIST_ITEMS:
        return data[:MAX_LIST_ITEMS] + [f"... ({len(data)-MAX_LIST_ITEMS} more)"]
    return data

def analyze_pods_content(content):
    issues = []
    lines = content.splitlines()
    if not lines: return []

    # Simple Heuristic: Skip header, look for restart counts > 0
    # Typical line: namespace name ready status restarts age ...
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 5: continue

        name = parts[1]
        status = parts[3]
        restarts = parts[4] # This might contain text like "10 (5m ago)"

        # Clean restart count (take first number)
        restart_count = 0
        match = re.match(r'(\d+)', restarts)
        if match:
            restart_count = int(match.group(1))

        # Criteria for "Bad Pod"
        is_crash = status in ["CrashLoopBackOff", "Error", "ContainerCreating", "Pending"]
        is_restarting = status == "Running" and restart_count > 0

        if is_crash:
            issues.append(f"CRASH: {name} ({status})")
        elif is_restarting:
            issues.append(f"UNSTABLE: {name} (Running, but {restart_count} restarts)")

    return issues

def analyze_bundle(bundle_path):
    # Detect Distro
    distro = "k3s" if os.path.exists(os.path.join(bundle_path, "k3s")) else "rke2"
    base = os.path.join(bundle_path, distro, "kubectl")

    # 1. Analyze Nodes
    nodes = safe_read(os.path.join(base, "nodes")) or ""
    not_ready = [l.split()[0] for l in nodes.splitlines() if "NotReady" in l]

    # 2. Analyze Pods (Smart Parse)
    pods_raw = safe_read(os.path.join(base, "pods")) or ""
    pod_issues = analyze_pods_content(pods_raw)

    # 3. Analyze Events
    events = safe_read(os.path.join(base, "events")) or ""
    warns = [l for l in events.splitlines() if "Warning" in l or "Failed" in l]

    return {
        "status": "Success",
        "distro": distro,
        "nodes": {"count": len(not_ready), "details": truncate_list(not_ready)},
        "pods": {"count": len(pod_issues), "details": truncate_list(pod_issues)},
        "events": {"count": len(warns), "sample": truncate_list(warns)}
    }

# =====================================================
# MCP PROTOCOL
# =====================================================
TOOLS = [
    {
        "name": "auto_diagnose",
        "description": "Scans for NotReady nodes, Crashing pods, and High Restart counts.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle_path": {"type": "string", "description": "Absolute path to bundle"}
            },
            "required": ["bundle_path"]
        }
    }
]

def process_request(req):
    method = req.get("method")
    msg_id = req.get("id")

    if method == "initialize":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {
            "protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "test_server", "version": "1.1"}
        }}

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {"tools": TOOLS}}

    if method == "tools/call":
        if req["params"]["name"] == "auto_diagnose":
            path = req["params"]["arguments"]["bundle_path"]
            result = analyze_bundle(path)
            return {"jsonrpc": "2.0", "id": msg_id, "result": {"content": [{"type": "text", "text": json.dumps(result, indent=2)}]}}

    return None

if __name__ == "__main__":
    while True:
        try:
            line = sys.stdin.readline()
            if not line: break
            resp = process_request(json.loads(line))
            if resp:
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
        except: continue
