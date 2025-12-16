#!/usr/bin/env python3
import sys
import json
import os
import subprocess

# --- PARANOID CONFIGURATION ---
MAX_LIST_ITEMS = 15       # Limit lists (e.g., pods) to 15 items
MAX_CHAR_LIMIT = 8000     # Limit file reads to ~8KB characters
MAX_LINE_LENGTH = 300     # Truncate individual log lines

# =====================================================
# Utility: Send Response
# =====================================================
def log_debug(msg):
    sys.stderr.write(f"[MCP-DEBUG] {msg}\n")
    sys.stderr.flush()

def send(response):
    try:
        json_str = json.dumps(response)
        if len(json_str) > 100000:
            log_debug(f"WARNING: Large response ({len(json_str)} bytes)")
        sys.stdout.write(json_str + "\n")
        sys.stdout.flush()
    except Exception as e:
        sys.stderr.write(f"JSON Dump Error: {e}\n")

# =====================================================
# Helper: Aggressive Truncation
# =====================================================
def truncate_line(line):
    if len(line) > MAX_LINE_LENGTH:
        return line[:MAX_LINE_LENGTH] + "...[TRUNCATED]"
    return line

def truncate_list(data_list):
    cleaned_list = [truncate_line(str(item)) for item in data_list]
    if len(cleaned_list) > MAX_LIST_ITEMS:
        remaining = len(cleaned_list) - MAX_LIST_ITEMS
        return cleaned_list[:MAX_LIST_ITEMS] + [f"... ({remaining} more items truncated)"]
    return cleaned_list

def safe_read(filepath):
    if not os.path.exists(filepath):
        return None
    try:
        file_size = os.path.getsize(filepath)
        if file_size > MAX_CHAR_LIMIT:
            with open(filepath, 'r', errors='replace') as f:
                head = f.read(MAX_CHAR_LIMIT // 2)
                f.seek(0, 2)
                tail_start = max(0, f.tell() - (MAX_CHAR_LIMIT // 2))
                f.seek(tail_start)
                tail = f.read()
                return f"{head}\n\n... [TRUNCATED {file_size - len(head) - len(tail)} bytes] ...\n\n{tail}"
        
        with open(filepath, 'r', errors='replace') as f:
            content = f.read()
            if len(content) > MAX_CHAR_LIMIT:
                return content[:MAX_CHAR_LIMIT] + "\n... [TRUNCATED SAFEGUARD]"
            return content
    except Exception as e:
        return f"Error reading file: {str(e)}"

# =====================================================
# TOOL: Core Functions
# =====================================================
def list_all(bundle):
    result = []
    for root, _, files in os.walk(bundle):
        if len(result) > MAX_LIST_ITEMS: break 
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), bundle)
            result.append(rel)
    return truncate_list(result)

def read_file(args):
    bundle = args.get("bundle", ".")
    file = args.get("file")
    full = os.path.join(bundle, file)
    content = safe_read(full)
    if content is None: return {"error": f"File not found: {full}"}
    return {"file": file, "content": content}

def analyze_events(args):
    bundle = args.get("bundle")
    distro = args.get("distro", "k3s")
    events_file = os.path.join(bundle, distro, "kubectl", "events")
    raw = safe_read(events_file) or ""
    lines = raw.splitlines()
    warnings = [l for l in lines if "Warning" in l or "Failed" in l]
    critical = [l for l in lines if "BackOff" in l or "Crashed" in l]
    return {
        "summary": f"Scanned {len(lines)} events. Found {len(warnings)} warnings, {len(critical)} critical.",
        "warnings_sample": truncate_list(warnings),
        "critical_sample": truncate_list(critical)
    }

def analyze_pods(args):
    bundle = args.get("bundle")
    distro = args.get("distro", "k3s")
    pods_file = os.path.join(bundle, distro, "kubectl", "pods")
    raw = safe_read(pods_file) or ""
    lines = raw.splitlines()
    crash = [l for l in lines if "Crash" in l or "Error" in l]
    pending = [l for l in lines if "Pending" in l]
    return {
        "summary": f"Scanned {len(lines)} pods. Found {len(crash)} crashing, {len(pending)} pending.",
        "crashloop_sample": truncate_list(crash),
        "pending_sample": truncate_list(pending)
    }

def analyze_nodes(args):
    bundle = args.get("bundle")
    distro = args.get("distro", "k3s")
    nodes_file = os.path.join(bundle, distro, "kubectl", "nodes")
    raw = safe_read(nodes_file) or ""
    lines = raw.splitlines()
    notready = [l for l in lines if "NotReady" in l]
    return {
        "summary": f"Scanned {len(lines)} nodes. Found {len(notready)} NotReady.",
        "not_ready_nodes": truncate_list(notready)
    }

def auto_diagnose(args):
    bundle = args.get("bundle", ".")
    distro = args.get("distro", "k3s")
    return {
        "events": analyze_events({"bundle": bundle, "distro": distro}),
        "nodes": analyze_nodes({"bundle": bundle, "distro": distro}),
        "pods": analyze_pods({"bundle": bundle, "distro": distro}),
        "note": "Data has been automatically truncated to fit context limits."
    }

# =====================================================
# Dispatcher
# =====================================================
def handle_call(tool, args):
    mapping = {
        "read_file": read_file,
        "list_files": lambda a: {"files": list_all(a.get("bundle", "."))},
        "auto_diagnose": auto_diagnose,
    }
    func = mapping.get(tool)
    if not func: return {"error": f"Tool '{tool}' not found."}
    return func(args)

# =====================================================
# Main Loop
# =====================================================
send({"status": "ready"})
for line in sys.stdin:
    if not line.strip(): continue
    try:
        request = json.loads(line)
        result = handle_call(request.get("tool"), request.get("arguments", {}))
        send({"result": result})
    except Exception as e:
        send({"error": str(e)})
