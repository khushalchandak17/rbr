# RBR (Rancher Bundle Reader)

A powerful, `kubectl`-like diagnostic tool for analyzing static Kubernetes/Rancher support bundles. RBR combines fast, local log parsing with an AI-driven Model Context Protocol (MCP) server to perform autonomous Root Cause Analysis (RCA) on offline clusters.

## Description

**RBR** transforms the tedious process of manually grep-ing through tarballed logs into a seamless CLI experience. It allows you to interact with an extracted support bundle as if it were a live cluster.

Beyond static analysis, RBR integrates with the **Gemini CLI** via a custom MCP server. This allows it to intelligently "read" the bundle, correlate events, analyze pod logs, and produce a Level 3 SRE diagnosis report automatically—even identifying issues like hidden RBAC failures or cascading crash loops.

## Goals

* **Simplify Diagnostics:** Make reading static bundles as easy as running `kubectl get pods`.
* **Automate RCA:** Leverage Large Language Models (LLMs) to connect the dots between disparate log files (Events, Pod Logs, Node Status) without manual intervention.
* **Standardize Analysis:** Provide a consistent toolset for support engineers handling RKE, RKE2, and K3s bundles.

## Features

* **Directory-Local Context:** Stateless execution—just `cd` into any extracted bundle and start debugging.
* **Kubectl Syntax:** Use familiar commands like `rbr get pods -n kube-system` or `rbr get events`.
* **Resource Discovery:** Instantly list all available resource types in the bundle with `rbr ls`.
* **AI-Powered Diagnosis:** The `rbr cs ai` command triggers a smart agent that investigates nodes, events, and logs to find the root cause of failures.
* **Smart Truncation:** Automatically filters and truncates massive logs to ensure AI analysis stays within token limits while retaining critical context.
* **Cross-Platform Sanitization:** Automatically handles file formatting issues (like Windows carriage returns) when reading logs.

## Prerequisites

To use the **AI features** (`rbr cs ai`), you need:
1.  **Python 3.x** installed.
2.  **Google GenAI SDK / Gemini CLI** installed.
3.  A valid **Google Gemini API Key**.

## Installation

### 1. Install RBR Tool

You can install RBR using the automated setup script. This will clone the repo to `/var/rbr` and create a symlink in `/usr/local/bin`.

```
curl -sfL https://raw.githubusercontent.com/khushalchandak17/rbr/main/setup.sh |  sudo bash
```


### 2. Configure AI (Gemini + MCP)

To enable the AI diagnostic features, you must configure the Gemini CLI to use the RBR Python server.

A. Locate the Server Script After installation, the python server is located at: /var/rbr/ai/cluster_bundle_debugger.py

B. Create the Settings File Create or edit your Gemini configuration file at ~/.gemini/settings.json:
```
mkdir -p ~/.gemini
vi ~/.gemini/settings.json
```

C. Paste Configuration Add the following configuration, ensuring the path matches your installation:
```
{
  "mcpServers": {
    "test_server": {
      "command": "/usr/bin/python3",
      "args": [
        "-u",
        "/Users/khushalchandak/mcp_test.py"
      ],
      "transport": "stdio"
    }
  },
  "security": {
    "auth": {
      "selectedType": "oauth-personal"
    },
    "alwaysAllow": [
      "test_server"
    ]
  }
}
```


# Usage

### Static Analysis (Manual)

Use RBR to explore the bundle manually using kubectl-like commands.

Step 1: Change directory to your extracted bundle.
```
cd /path/to/extracted/bundle/folder
```
Step 2: Run commands.
```
# List all available resources in the bundle
rbr ls

# Get all pods
rbr get pods

# Get pods in a specific namespace
rbr get pods -n kube-system

# Get events, services, or nodes
rbr get events
rbr get svc
rbr get nodes
```


### AI Diagnosis (Automatic)

Let the AI analyze the cluster for you.

```
# Run the AI Root Cause Analysis
rbr ai cs
rbr ai pods
rbr ai events
```

