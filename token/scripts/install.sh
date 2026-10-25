#!/usr/bin/env bash
# On any machine: install this folder as ~/.claude/skills/token and set up graphify.
set -eu
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$HOME/.claude/skills/token"
if [ "$SRC" != "$DST" ]; then mkdir -p "$HOME/.claude/skills"; rm -rf "$DST"; cp -R "$SRC" "$DST"; echo "copied → $DST"; fi
chmod +x "$DST/scripts/"*.sh
bash "$DST/scripts/token.sh" ensure
echo "ready: type /token in Claude Code"
