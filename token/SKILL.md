---
name: token
description: "Save tokens with a project code map. Builds/updates a code map of the current project (graphify, local AST, no LLM calls), writes an 'ask the map first' rule into the project, and stops Claude from re-scanning the whole project. Triggers: /token, 'map the project', 'build a code map', 'reduce tokens', 'save tokens', 'project map', 'install graphify', when starting code exploration in a new project, or when the user complains 'you keep re-reading the whole project'. Installs graphify itself if missing; the same folder works on any machine."
---

# token — fewer tokens with a project map

Everything runs through `scripts/token.sh` (deterministic, no LLM calls). The script produces the numbers; you interpret them.

## Flow (every invocation, in order)

1. **Install/verify** — `bash ~/.claude/skills/token/scripts/token.sh ensure`
   Exit code 3 means graphify could not be installed: give the user the install lines the script printed, verbatim, and stop.
2. **Status** — `bash ~/.claude/skills/token/scripts/token.sh status <project-root>`
   Exit 2 (no map) or 4 (stale) → go to step 3; exit 0 → skip to step 4.
3. **Build/update** — `bash ~/.claude/skills/token/scripts/token.sh build <project-root>`
   The script first writes code-extension files with an XML body (Tiled tilesets etc.) to `.graphifyignore`, then runs `graphify update`, then prints the status. If the user says "from scratch", add `--force`.
4. **Write the project rule** (first time, or if missing) — `bash ~/.claude/skills/token/scripts/token.sh install-project <project-root>`
   Adds a marked block to the project's `CLAUDE.md` (idempotent). Only if the user explicitly says "enforce / strict", add `--strict`: installs a Claude Code PreToolUse hook so the session's first raw file read is blocked until a `graphify query` has run.
5. **Report** — give the numbers from `status` as-is: nodes/edges, GRAPH_REPORT ≈ tokens, raw source ≈ tokens, freshness. Never invent savings figures beyond what the script printed.

Project root: if the user didn't specify, `git rev-parse --show-toplevel`, otherwise the working directory. Don't ask.

## When answering questions
If a map exists, for a code question run this **before** the first grep/Read:
`bash ~/.claude/skills/token/scripts/token.sh query "<question>" <project-root>` — the token count is printed at the end. Open raw files only for the lines the query points to. Never read `graphify-out/graph.json` as a whole.

## Limits (tell the user, don't hide them)
- The map covers code only (tree-sitter, 30 languages). Docs/PDFs/images need an LLM; this skill doesn't run one.
- Some files may yield no symbols (e.g. plain PHP scripts, `vite.config.ts`); the script shows them with a "no symbols" warning. Those need raw reads.
- Savings depend on the task: large for "where is the flow / what calls this" questions (measured example: 169k → 2.9k tokens); small for a one-file fix.
- The map goes stale when code changes. `query` checks freshness first and runs `update` automatically if any code file is newer than the map (it prints a `map was stale` line), so renamed/moved symbols don't come back with old locations. Plain `graphify query` (without token.sh) does NOT do this check.

## Another machine
The skill folder is self-contained: copy `~/.claude/skills/token/`, run `bash ~/.claude/skills/token/scripts/install.sh` (or just `/token`). `ensure` installs graphify: `uv` first, then `pipx`, then `python3 -m venv ~/.local/share/token-skill/venv` (PEP 668 Homebrew/Debian Python rejects `pip --user`; a venv works everywhere). Measured: 93 s on a clean environment with only python3. Requirements: Python 3.10+ and internet. The block in the project's `CLAUDE.md` travels with the project; `graphify-out/` is rebuilt with `build` in seconds on each machine, no syncing needed. Windows: the script needs bash (Git Bash/WSL); native PowerShell is not supported.
