#!/usr/bin/env python3
import sys
import json
import os
import subprocess

# --- CONFIGURATION ---
MAX_LIST_ITEMS = 15
MAX_CHAR_LIMIT = 8000
MAX_LINE_LENGTH = 300

# =====================================================
# CORE LOGIC (Truncation & Analysis)
# =====================================================
def safe_read(filepath):
    """Reads a file with a hard character cap."""
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

def truncate_list(data_list):
    """Truncates list items and list length."""
    cleaned = [str(x)[:MAX_LINE_LENGTH] + ("..." if len(str(x)) > MAX_LINE_LENGTH else "") for x in data_list]
    if len(cleaned) > MAX_LIST_ITEMS:
        rem = len(cleaned) - MAX_LIST_ITEMS
        return cleaned[:MAX_LIST_ITEMS] + [f"... ({rem} more items truncated)"]
    return cleaned

def list_all_files(bundle):
    result = []
    for root, _, files in os.walk(bundle):
        if len(result) > MAX_LIST_ITEMS: break
        for f in files:
            result.append(os.path.relpath(os.path.join(root, f), bundle))
    return truncate_list(result)

def analyze_events(bundle, distro):
    path = os.path.join(bundle, distro, "kubectl", "events")
    raw = safe_read(path) or ""
    lines = raw.splitlines()
    warnings = [l for l in lines if "Warning" in l or "Failed" in l]
    critical = [l for l in lines if "BackOff" in l or "Crashed" in l]
    return {
        "summary": f"Scanned {len(lines)} events. Found {len(warnings)} warnings, {len(critical)} critical.",
        "warnings_sample": truncate_list(warnings),
        "critical_sample": truncate_list(critical)
    }

def analyze_pods(bundle, distro):
    path = os.path.join(bundle, distro, "kubectl", "pods")
    raw = safe_read(path) or ""
    lines = raw.splitlines()
    crash = [l for l in lines if "Crash" in l or "Error" in l]
    pending = [l for l in lines if "Pending" in l]
    return {
        "summary": f"Scanned {len(lines)} pods. Found {len(crash)} crashing, {len(pending)} pending.",
        "crashloop_sample": truncate_list(crash),
        "pending_sample": truncate_list(pending)
    }

def analyze_nodes(bundle, distro):
    path = os.path.join(bundle, distro, "kubectl", "nodes")
    raw = safe_read(path) or ""
    lines = raw.splitlines()
    notready = [l for l in lines if "NotReady" in l]
    return {
        "summary": f"Scanned {len(lines)} nodes. Found {len(notready)} NotReady.",
        "not_ready_nodes": truncate_list(notready)
    }

def auto_diagnose(bundle, distro):
    return {
        "events": analyze_events(bundle, distro),
        "nodes": analyze_nodes(bundle, distro),
        "pods": analyze_pods(bundle, distro),
        "note": "Data has been automatically truncated to fit context limits."
    }

# =====================================================
# MCP PROTOCOL HANDLING (The Fix)
# =====================================================

TOOLS = [
    {
        "name": "auto_diagnose",
        "description": "PRIMARY TOOL. Runs a full diagnostic scan on the cluster bundle (Nodes, Pods, Events).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle": {"type": "string", "description": "Absolute path to bundle root"},
                "distro": {"type": "string", "description": "k3s or rke2"}
            },
            "required": ["bundle"]
        }
    },
    {
        "name": "read_file",
        "description": "Reads a specific file from the bundle safely.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle": {"type": "string"},
                "file": {"type": "string", "description": "Relative path to file"}
            },
            "required": ["bundle", "file"]
        }
    },
    {
        "name": "list_files",
        "description": "Lists files in the bundle.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "bundle": {"type": "string"}
            },
            "required": ["bundle"]
        }
    }
]

def handle_call_tool(name, args):
    if name == "auto_diagnose":
        return auto_diagnose(args.get("bundle", "."), args.get("distro", "k3s"))
    elif name == "read_file":
        full_path = os.path.join(args.get("bundle", "."), args.get("file", ""))
        content = safe_read(full_path)
        if content is None: return f"Error: File not found: {full_path}"
        return content
    elif name == "list_files":
        return list_all_files(args.get("bundle", "."))
    raise ValueError(f"Unknown tool: {name}")

def process_request(request):
    method = request.get("method")
    msg_id = request.get("id")
    params = request.get("params", {})

    # Handshake: initialize
    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "rbr-debugger", "version": "1.0"}
            }
        }
    
    # Handshake: initialized (notification, no response needed)
    if method == "notifications/initialized":
        return None

    # Capabilities: tools/list
    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {"tools": TOOLS}
        }

    # Execution: tools/call
    if method == "tools/call":
        try:
            name = params.get("name")
            args = params.get("arguments", {})
            result = handle_call_tool(name, args)
            return {
                "jsonrpc": "2.0", 
                "id": msg_id, 
                "result": {"content": [{"type": "text", "text": json.dumps(result, indent=2)}]}
            }
        except Exception as e:
            return {
                "jsonrpc": "2.0", 
                "id": msg_id, 
                "error": {"code": -32000, "message": str(e)}
            }
    
    # Ping or unknown
    if method == "ping":
         return {"jsonrpc": "2.0", "id": msg_id, "result": {}}

    return None

def main():
    # Read from stdin, write to stdout
    while True:
        try:
            line = sys.stdin.readline()
            if not line: break
            
            request = json.loads(line)
            response = process_request(request)
            
            if response:
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
                
        except (json.JSONDecodeError, ValueError):
            continue
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    main()
