#!/bin/bash
#
# RBR Installation Script
# Downloads and installs the RBR utility to /var/rbr/
# Creates a symlink in /usr/local/bin or another suitable $PATH directory.

# --- Configuration ---
# 1. Installation Directory
RBR_DIR="/var/rbr"
# 2. GitHub Repository Details
REPO_OWNER="khushalchandak17"
REPO_NAME="rbr"
REPO_BRANCH="main"
# 3. Target Executable Name (The symlink target)
TARGET_EXECUTABLE="rbr"

# --- Function Definitions ---

# Function to safely find a writable directory in $PATH for the symlink
find_bin_dir() {
  local dir
  # Check common paths first, then fall back to iterating through $PATH
  for dir in /usr/local/bin /usr/bin ~/bin; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      echo "$dir"
      return 0
    fi
  done

  # Check paths listed in $PATH
  echo "$PATH" | tr ':' '\n' | while read -r dir; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      echo "$dir"
      return 0
    fi
  done

  return 1
}

# --- Main Installation Logic ---

echo "========================================"
echo "🚀 RBR (Rancher Bundle Reader) Installer"
echo "========================================"

# Check for required tools
if ! command -v git &> /dev/null; then
  echo "Error: 'git' is required to clone the repository. Please install git." >&2
  exit 1
fi

# Step 1: Check for root/sudo privileges (necessary for /var installation)
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run with root privileges (using sudo)." >&2
  exit 1
fi

# Step 2: Remove existing installation directory (if any)
if [ -d "$RBR_DIR" ]; then
  echo "Removing existing directory: $RBR_DIR"
  rm -rf "$RBR_DIR"
fi

# Step 3: Create the installation directory
echo "Creating installation directory: $RBR_DIR"
mkdir -p "$RBR_DIR"

# Step 4: Clone the GitHub repository directly into the installation directory
REPO_URL="https://github.com/$REPO_OWNER/$REPO_NAME.git"
echo "Cloning repository from $REPO_URL to $RBR_DIR"
if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$RBR_DIR"; then
  echo "Error: Failed to clone repository." >&2
  rm -rf "$RBR_DIR"
  exit 1
fi

# Step 5: Ensure scripts are executable
echo "Setting executable permissions..."

# 5a. Core CLI script
CORE_SCRIPT="$RBR_DIR/bin/$TARGET_EXECUTABLE.sh"
if [ -f "$CORE_SCRIPT" ]; then
  chmod +x "$CORE_SCRIPT"
else
  echo "Error: Core script $CORE_SCRIPT not found after clone." >&2
  rm -rf "$RBR_DIR"
  exit 1
fi

# 5b. AI Server script
if [ -f "$RBR_DIR/ai/cluster_bundle_debugger.py" ]; then
  chmod +x "$RBR_DIR/ai/cluster_bundle_debugger.py"
fi

# 5c. Bundled Diagnostic Data scripts
if [ -f "$RBR_DIR/data/cluster-summary.sh" ]; then
  chmod +x "$RBR_DIR/data/cluster-summary.sh"
  # Recursively make lib scripts executable if they exist
  if [ -d "$RBR_DIR/data/lib" ]; then
      chmod +x "$RBR_DIR/data/lib/"*.sh
  fi
fi

# Step 6: Create a symlink in $PATH
BIN_DIR=$(find_bin_dir)
if [ -z "$BIN_DIR" ]; then
  echo "Warning: Could not find a writable directory in \$PATH. Symlink skipped."
  echo "To run RBR, use the full path: $CORE_SCRIPT"
  exit 0
fi

SYMLINK_PATH="$BIN_DIR/$TARGET_EXECUTABLE"

# A small wrapper function to execute the core script
WRAPPER_SCRIPT="$RBR_DIR/$TARGET_EXECUTABLE"

# Create a simple wrapper script that executes the core script
echo "#!/bin/bash" > "$WRAPPER_SCRIPT"
echo "exec $CORE_SCRIPT \"\$@\"" >> "$WRAPPER_SCRIPT"
chmod +x "$WRAPPER_SCRIPT"

if [ -L "$SYMLINK_PATH" ]; then
  echo "Removing existing symlink: $SYMLINK_PATH"
  rm -f "$SYMLINK_PATH"
fi

echo "Creating symlink: $SYMLINK_PATH -> $RBR_DIR/$TARGET_EXECUTABLE"
if ! ln -s "$WRAPPER_SCRIPT" "$SYMLINK_PATH"; then
  echo "Error: Failed to create symlink at $SYMLINK_PATH." >&2
  exit 1
fi

# Step 7: Verify installation and usage instructions
if command -v "$TARGET_EXECUTABLE" &> /dev/null; then
  echo "----------------------------------------"
  echo "✅ RBR Installation Completed Successfully."
  echo "   Use 'rbr help' for usage."
  echo "   NOTE: You must 'cd' into the extracted bundle directory first."
  echo "----------------------------------------"
else
  echo "Error: Installation failed. Symlink not found in PATH." >&2
  exit 1
fi
