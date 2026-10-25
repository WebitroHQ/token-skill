#!/usr/bin/env bash
# token — deterministic helper for a project code map (graphify).
# Usage:
#   token.sh ensure                  is graphify installed; if not, install it (uv → pipx → venv)
#   token.sh build [path] [--force]  build/rebuild the map (AST, no LLM) + status
#   token.sh update [path]           same as build (alias for readability)
#   token.sh status [path]           does the map exist, is it fresh, size/token summary
#   token.sh query "question" [path] graphify query + output token count
#   token.sh ignore-scan [path]      write code-extension files with an XML body to .graphifyignore
#   token.sh install-project [path] [--strict]  add a persistent "ask the map first" rule to the project (+ hook)
# Exit codes: 0 ok · 1 error · 3 graphify could not be installed (instructions are printed)
set -u
export PATH="$HOME/.local/bin:$HOME/Library/Python/3.14/bin:$HOME/.pyenv/shims:$PATH"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARK_A="# >>> token-skill (auto-generated; do not edit) >>>"
MARK_B="# <<< token-skill <<<"
# python3 on Windows may be a Microsoft Store stub; use the first interpreter that actually runs
PY=""; for c in python3 python; do "$c" -c 'import sys' >/dev/null 2>&1 && { PY="$c"; break; }; done

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

root_of() {
  local p="${1:-.}"
  p="$(cd "$p" 2>/dev/null && pwd)" || die "no such path: $1"
  git -C "$p" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$p"
}

tokens_of_file() { awk '{c+=length($0)+1} END{printf "%d", c/4}' "$1" 2>/dev/null; }

code_tokens() { # rough token estimate of source code (chars/4); generated/binary dirs excluded
  find "$1" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \
    -o -name '*.py' -o -name '*.php' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.swift' \
    -o -name '*.rb' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.cs' -o -name '*.vue' -o -name '*.svelte' \
    -o -name '*.css' -o -name '*.scss' -o -name '*.md' -o -name '*.sql' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.next/*' -not -path '*/dist/*' -not -path '*/build/*' \
    -not -path '*/graphify-out/*' -not -path '*/vendor/*' -not -path '*/.venv/*' -not -name '*.min.*' -not -name '*-lock.json' \
    -print0 2>/dev/null | xargs -0 cat 2>/dev/null | awk '{c+=length($0)+1} END{printf "%d", c/4}'
}

cmd_ensure() {
  if command -v graphify >/dev/null 2>&1; then
    say "graphify: $(graphify --version 2>/dev/null | grep -vE '▄|█|▀' | head -1) ($(command -v graphify))"
  else
    say "graphify not found, installing..."
    local log; log="$(mktemp)"
    if command -v uv >/dev/null 2>&1; then
      say "  method: uv tool install"; uv tool install graphifyy >>"$log" 2>&1 || uv tool upgrade graphifyy >>"$log" 2>&1
    elif command -v pipx >/dev/null 2>&1; then
      say "  method: pipx install"; pipx install graphifyy >>"$log" 2>&1
    fi
    if ! command -v graphify >/dev/null 2>&1 && [ -n "$PY" ]; then
      # PEP 668 (Homebrew/Debian Python) rejects 'pip --user'; a venv works everywhere.
      local vdir="$HOME/.local/share/token-skill/venv" vbin="bin"
      say "  method: $PY -m venv $vdir"
      if "$PY" -m venv "$vdir" >>"$log" 2>&1; then
        [ -d "$vdir/Scripts" ] && vbin="Scripts"  # Windows venvs use Scripts/
        "$vdir/$vbin/python" -m pip install --quiet graphifyy >>"$log" 2>&1 \
          && mkdir -p "$HOME/.local/bin" && ln -sf "$vdir/$vbin/graphify" "$HOME/.local/bin/graphify" && ln -sf "$vdir/$vbin/graphify-mcp" "$HOME/.local/bin/graphify-mcp"
      fi
    fi
    if ! command -v graphify >/dev/null 2>&1; then
      say "graphify could not be installed. Last error lines:" >&2; tail -5 "$log" >&2; rm -f "$log"
      say "Install manually (pick one), then retry:" >&2
      say "  uv tool install graphifyy     # https://docs.astral.sh/uv/" >&2
      say "  pipx install graphifyy" >&2
      say "  python3 -m venv ~/.local/share/token-skill/venv && ~/.local/share/token-skill/venv/bin/pip install graphifyy" >&2
      exit 3
    fi
    rm -f "$log"
    say "graphify installed: $(command -v graphify)"
  fi
  if [ ! -f "$HOME/.claude/skills/graphify/SKILL.md" ]; then
    say "registering the graphify skill with Claude Code (global)..."
    graphify install --platform claude >/dev/null 2>&1 || say "warning: 'graphify install' failed; /graphify may not work, token.sh still works" >&2
  fi
}

cmd_ignore_scan() {
  local root; root="$(root_of "${1:-.}")"
  local list
  list="$(find "$root" -type f \( -name '*.tsx' -o -name '*.ts' -o -name '*.js' -o -name '*.jsx' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/graphify-out/*' -print0 2>/dev/null \
    | xargs -0 grep -lE '^\s*<\?xml|^\s*<!DOCTYPE' 2>/dev/null | sed "s#^$root/##" | sort)"
  local f="$root/.graphifyignore" tmp; tmp="$(mktemp)"
  # strip the old token block from the existing file
  if [ -f "$f" ]; then awk -v a="$MARK_A" -v b="$MARK_B" '$0==a{skip=1;next} $0==b{skip=0;next} !skip' "$f" > "$tmp"; fi
  if [ -n "$list" ]; then
    { cat "$tmp"; say "$MARK_A"; say "# files with a code extension but an XML body (Tiled tilesets etc.) — they break the AST"; printf '%s\n' "$list"; say "$MARK_B"; } > "$f"
    say "ignore: $(printf '%s\n' "$list" | wc -l | tr -d ' ') XML-body files written to .graphifyignore"
  else
    if [ -s "$tmp" ]; then cp "$tmp" "$f"; elif [ -f "$f" ]; then rm -f "$f"; fi
    say "ignore: no XML-body code files"
  fi
  rm -f "$tmp"
}

cmd_status() {
  local root; root="$(root_of "${1:-.}")"
  local g="$root/graphify-out/graph.json" r="$root/graphify-out/GRAPH_REPORT.md"
  say "project: $root"
  if [ ! -f "$g" ]; then say "map: NONE  → run 'token.sh build'"; return 2; fi
  PYTHONIOENCODING=utf-8 "${PY:-python3}" - "$g" <<'PY'
import json,sys,os
g=json.load(open(sys.argv[1], encoding="utf-8")); n=g.get("nodes",[]); e=g.get("edges") or g.get("links") or []
comms=len({x.get("community") for x in n if x.get("community") is not None})
print(f"map: {len(n)} nodes · {len(e)} edges · {comms} communities · graph.json {os.path.getsize(sys.argv[1])//1024} KB")
PY
  local rt ct; rt="$(tokens_of_file "$r")"; ct="$(code_tokens "$root")"
  say "tokens: GRAPH_REPORT.md ≈ $rt · raw source ≈ $ct · query output typically 0.5–4k"
  # freshness: any code file newer than the map?
  local newer; newer="$(find "$root" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.php' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.md' \) \
    -newer "$g" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/graphify-out/*' -not -path '*/.next/*' -not -path '*/dist/*' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$newer" -gt 0 ]; then say "freshness: STALE — $newer files changed since the map → 'token.sh update'"; return 4; else say "freshness: up to date"; fi
}

cmd_build() {
  local root; root="$(root_of "${1:-.}")"; shift || true
  local force=""; for a in "$@"; do [ "$a" = "--force" ] && force="--force"; done
  cmd_ensure || return $?
  cmd_ignore_scan "$root"
  local t0; t0="$(date +%s)"
  graphify update "$root" $force 2>&1 | grep -vE '▄|█|▀|^\s*$' | grep -E 'Rebuilt|warning|error|Error' | cut -c1-220
  say "time: $(( $(date +%s) - t0 )) s"
  cmd_status "$root"
}

cmd_query() {
  local q="${1:?question required}"; local root; root="$(root_of "${2:-.}")"
  [ -f "$root/graphify-out/graph.json" ] || die "no map: run 'token.sh build $root' first"
  local out; out="$(cd "$root" && graphify query "$q" 2>&1)"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | awk '{c+=length($0)+1} END{printf "[tokens: query output ≈ %d]\n", c/4}'
}

cmd_install_project() {
  local root; root="$(root_of "${1:-.}")"; shift || true
  local strict=""; for a in "$@"; do [ "$a" = "--strict" ] && strict="--strict"; done
  local md="$root/CLAUDE.md" tmp; tmp="$(mktemp)"
  [ -f "$md" ] && awk -v a="$MARK_A" -v b="$MARK_B" '$0==a{skip=1;next} $0==b{skip=0;next} !skip' "$md" > "$tmp"
  { cat "$tmp"; [ -s "$tmp" ] && say ""; say "$MARK_A"; cat "$SKILL_DIR/templates/project-claude-md.md"; say "$MARK_B"; } > "$md"
  rm -f "$tmp"; say "CLAUDE.md: token rule written → $md"
  if [ -n "$strict" ]; then
    cmd_ensure || return $?
    (cd "$root" && graphify install --project --strict --platform claude 2>&1 | grep -E 'settings.json|CLAUDE.md|skill' | cut -c1-160)
    say "strict: the first raw file read is blocked until a 'graphify query' runs (disable with GRAPHIFY_HOOK_STRICT=0)"
  fi
}

case "${1:-}" in
  ensure) cmd_ensure ;;
  build|update) shift; cmd_build "$@" ;;
  status) shift; cmd_status "$@" ;;
  query) shift; cmd_query "$@" ;;
  ignore-scan) shift; cmd_ignore_scan "$@" ;;
  install-project) shift; cmd_install_project "$@" ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
