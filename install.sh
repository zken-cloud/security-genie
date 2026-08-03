#!/usr/bin/env bash
# install.sh — install the Security Genie harness, skills, and guard hooks for coding agents.
# Usage: ./install.sh [--agent claude|codex|gemini|antigravity|all] [--global|--project]
#                     [--link] [--target DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="all"
SCOPE="project"
LINK=0
TARGET="$PWD"

usage() { sed -n '2,4p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:?--agent needs a value}"; shift 2 ;;
    --global) SCOPE="global"; shift ;;
    --project) SCOPE="project"; shift ;;
    --link) LINK=1; shift ;;
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

place_skills() { # $1 = destination skills dir
  local dest="$1" d name
  mkdir -p "$dest"
  for d in "$ROOT"/skills/*/; do
    name="$(basename "$d")"
    if [ "$LINK" = 1 ]; then
      ln -sfn "$ROOT/skills/$name" "$dest/$name"
    else
      rm -rf "$dest/$name"
      cp -R "$d" "$dest/$name"
    fi
  done
  echo "  skills -> $dest"
}

install_guard() { # $1 = destination hooks dir
  mkdir -p "$1"
  cp "$ROOT/hooks/dangerous_command_guard.py" "$1/dangerous_command_guard.py"
  chmod +x "$1/dangerous_command_guard.py"
  echo "  guard hook -> $1/dangerous_command_guard.py"
}

copy_if_absent() { # $1 = src file, $2 = dest file
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ]; then
    echo "  exists, skipped: $2"
  else
    cp "$1" "$2"
    echo "  created: $2"
  fi
}

copy_settings() { # $1 = src, $2 = dest — like copy_if_absent but with a merge hint
  if [ -e "$2" ]; then
    echo "  exists: merge the hooks/mcpServers blocks from $1 into $2"
  else
    mkdir -p "$(dirname "$2")"
    cp "$1" "$2"
    echo "  created: $2"
  fi
}

install_harness_files() { # project scope only; $1 = agent name
  copy_if_absent "$ROOT/AGENTS.md" "$TARGET/AGENTS.md"
  case "$1" in
    claude) copy_if_absent "$ROOT/CLAUDE.md" "$TARGET/CLAUDE.md" ;;
    gemini|antigravity) copy_if_absent "$ROOT/GEMINI.md" "$TARGET/GEMINI.md" ;;
  esac
}

install_claude() {
  echo "[claude-code]"
  if [ "$SCOPE" = global ]; then
    place_skills "$HOME/.claude/skills"
    install_guard "$HOME/.claude/hooks"
    echo "  hooks: register a PreToolUse Bash hook running: python3 \$HOME/.claude/hooks/dangerous_command_guard.py"
    echo "  MCP (user scope): claude mcp add gcloud -- npx -y @google-cloud/gcloud-mcp"
  else
    place_skills "$TARGET/.claude/skills"
    copy_if_absent "$ROOT/.mcp.json" "$TARGET/.mcp.json"
    install_guard "$TARGET/.claude/hooks"
    copy_settings "$ROOT/hooks/claude-settings.json" "$TARGET/.claude/settings.json"
    install_harness_files claude
  fi
}

install_codex() {
  echo "[codex]"
  if [ "$SCOPE" = global ]; then
    place_skills "$HOME/.codex/skills"
    install_guard "$HOME/.codex/hooks"
    copy_settings "$ROOT/hooks/codex-hooks.json" "$HOME/.codex/hooks.json"
    echo "  hooks: experimental — add '[features]' + 'hooks = true' to ~/.codex/config.toml (VERIFY against your Codex version)"
    echo "  MCP: merge [mcp_servers.gcloud] from $ROOT/.codex/config.toml into ~/.codex/config.toml"
  else
    place_skills "$TARGET/.agents/skills"
    copy_if_absent "$ROOT/.codex/config.toml" "$TARGET/.codex/config.toml"
    install_harness_files codex
    echo "  hooks: Codex hooks are user-level only — run: $0 --agent codex --global"
  fi
}

install_gemini() {
  echo "[gemini-cli]"
  if [ "$SCOPE" = global ]; then
    place_skills "$HOME/.gemini/skills"
    install_guard "$HOME/.gemini/hooks"
    echo "  hooks: merge the hooks block from $ROOT/hooks/gemini-settings.json into ~/.gemini/settings.json"
    echo "  MCP: npx @google-cloud/gcloud-mcp init --agent=gemini-cli"
  else
    place_skills "$TARGET/.gemini/skills"
    install_guard "$TARGET/.gemini/hooks"
    copy_settings "$ROOT/hooks/gemini-settings.json" "$TARGET/.gemini/settings.json"
    install_harness_files gemini
  fi
}

install_antigravity() {
  echo "[antigravity (agy)]"
  if [ "$SCOPE" = global ]; then
    place_skills "$HOME/.gemini/antigravity/skills"
    install_guard "$HOME/.gemini/hooks"
    echo "  hooks: agy shares the Gemini CLI settings format — merge the hooks block from $ROOT/hooks/gemini-settings.json into ~/.gemini/settings.json (VERIFY)"
    echo "  MCP: copy the 'gcloud' entry from $ROOT/.mcp.json into ~/.gemini/antigravity/mcp_config.json"
  else
    place_skills "$TARGET/.agents/skills"
    install_guard "$TARGET/.gemini/hooks"
    copy_settings "$ROOT/hooks/gemini-settings.json" "$TARGET/.gemini/settings.json"
    install_harness_files antigravity
  fi
}

case "$AGENT" in
  claude) install_claude ;;
  codex) install_codex ;;
  gemini) install_gemini ;;
  antigravity) install_antigravity ;;
  all) install_claude; install_codex; install_gemini; install_antigravity ;;
  *) echo "unknown agent: $AGENT" >&2; usage 1 ;;
esac

echo "done."
