#!/usr/bin/env bash
# Prepares an Ubuntu 22.04/24.04 machine (that already runs, or will run, a GHES self-hosted
# Actions runner) for the Copilot agents: git, jq, curl, GitHub CLI, Node.js 22 and Copilot CLI.
#
# Usage:
#   sudo ./setup-runner.sh [--ca-cert /path/to/ghes-ca.crt] [--runner-dir /home/runner/actions-runner]
#
#   --ca-cert     Only needed when GHES uses a certificate from a private/self-signed CA.
#                 The CA is added to the system trust store, which the workflows point Node at.
#   --runner-dir  Runner install dir; NODE_EXTRA_CA_CERTS is added to its .env and the service restarted.
set -euo pipefail

CA_CERT=""
RUNNER_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ca-cert) CA_CERT="$2"; shift 2 ;;
    --runner-dir) RUNNER_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "==> Base packages"
apt-get update -q
apt-get install -y -q git jq curl ca-certificates gnupg

echo "==> GitHub CLI"
if ! command -v gh >/dev/null; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -q && apt-get install -y -q gh
fi

echo "==> Node.js 22"
node_major="$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || echo 0)"
if [ "${node_major:-0}" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -q nodejs
fi

echo "==> Copilot CLI"
npm install -g @github/copilot

if [ -n "$CA_CERT" ]; then
  echo "==> Trusting GHES CA $CA_CERT"
  cp "$CA_CERT" /usr/local/share/ca-certificates/ghes-ca.crt
  update-ca-certificates
fi

if [ -n "$RUNNER_DIR" ]; then
  echo "==> Configuring runner at $RUNNER_DIR"
  env_file="$RUNNER_DIR/.env"
  touch "$env_file"
  grep -q '^NODE_EXTRA_CA_CERTS=' "$env_file" \
    || echo "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt" >> "$env_file"
  if [ -x "$RUNNER_DIR/svc.sh" ]; then
    (cd "$RUNNER_DIR" && ./svc.sh stop && ./svc.sh start) || echo "Restart the runner service manually."
  fi
fi

echo
for t in git gh jq node copilot; do printf '%-8s %s\n' "$t" "$($t --version 2>/dev/null | head -1)"; done
echo
echo "Done. Make sure the runner has the label 'copilot-agent' (or pass runner-label to the workflows)."
