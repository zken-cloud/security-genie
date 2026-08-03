#!/usr/bin/env bash
# run-sast.sh — open-source SAST: Semgrep for application code, Checkov/Trivy/tfsec for Terraform.
# Usage: scripts/run-sast.sh [--code DIR] [--terraform DIR] [--out DIR]
# With no flags: scans "." as Terraform if it contains .tf files, otherwise as code.
# Tools must already be installed (isolated installs only — pipx/venv/docker, never system pip).
# Semgrep registry configs (p/*) require network access.
set -uo pipefail

CODE=""
TF=""

usage() { sed -n '2,6p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --code) CODE="${2:?--code needs a directory}"; shift 2 ;;
    --terraform|--tf) TF="${2:?--terraform needs a directory}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [ -z "$CODE" ] && [ -z "$TF" ]; then
  if ls ./*.tf >/dev/null 2>&1; then TF="."; else CODE="."; fi
fi

have() { command -v "$1" >/dev/null 2>&1; }

scan_code() { # $1 = dir
  local dir="$1"
  if have semgrep; then
    echo "== semgrep (p/security-audit + p/secrets): $dir"
    semgrep scan --config p/security-audit --config p/secrets --metrics=off "$dir"
  else
    echo "semgrep not found. Install isolated, e.g.:" >&2
    echo "  pipx install semgrep" >&2
    echo "  python3 -m venv ~/.venv-sast && ~/.venv-sast/bin/pip install semgrep" >&2
    return 1
  fi
}

scan_terraform() { # $1 = dir
  local dir="$1"
  if have checkov; then
    echo "== checkov (terraform): $dir"
    checkov -d "$dir" --framework terraform --compact --soft-fail
  elif have trivy; then
    echo "== trivy config: $dir"
    trivy config "$dir"
  elif have tfsec; then
    echo "== tfsec (deprecated upstream; consider trivy config): $dir"
    tfsec "$dir" --soft-fail
  elif have semgrep; then
    echo "== semgrep (p/terraform): $dir"
    semgrep scan --config p/terraform --metrics=off "$dir"
  else
    echo "no Terraform scanner found. Install isolated, e.g.:" >&2
    echo "  pipx install checkov   # or: trivy / tfsec" >&2
    echo "  python3 -m venv ~/.venv-sast && ~/.venv-sast/bin/pip install checkov" >&2
    return 1
  fi
}

status=0
if [ -n "$CODE" ]; then scan_code "$CODE" || status=1; fi
if [ -n "$TF" ]; then scan_terraform "$TF" || status=1; fi
exit "$status"
