#!/usr/bin/env bash
set -euo pipefail

RESOURCE="${1:-}"

if [[ -z "$RESOURCE" ]]; then
  echo "Usage: rbr get <resource>"
  exit 1
fi

# detect distro
if [[ -d k3s ]]; then
  DISTRO="k3s"
elif [[ -d rke2 ]]; then
  DISTRO="rke2"
else
  echo "❌ Not inside a k3s or rke2 bundle"
  exit 1
fi

FILE="$DISTRO/kubectl/$RESOURCE"

if [[ ! -f "$FILE" ]]; then
  echo "❌ Resource file not found: $FILE"
  exit 1
fi

cat "$FILE"

