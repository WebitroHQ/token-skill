# token — a Claude Code skill that stops re-reading your whole project

`token` gives Claude Code a **code map** of your project and a rule to **ask the map first**, so it stops grepping and reading file after file every time you ask "where does X happen?".

The map is built locally by [graphify](https://github.com/Graphify-Labs/graphify) from the AST (tree-sitter, 30 languages). **No LLM calls, no API key, nothing leaves your machine.** Building a map takes seconds.

```
/token
```
```
map: 63 nodes · 176 edges · 8 communities · graph.json 48 KB
tokens: GRAPH_REPORT.md ≈ 651 · raw source ≈ 21551 · query output typically 0.5–4k
freshness: up to date
CLAUDE.md: token rule written → ./CLAUDE.md
```

## Why

On a code-navigation question, Claude usually explores: grep, open a file, open three more, repeat. On a mid-sized project that can easily be 100k+ tokens of raw source before it answers. A graph query returns the relevant symbols, files and line numbers in a few hundred to a few thousand tokens, and Claude then opens only those lines.

Measured example (one "how does this flow work" question on a real project): **~169k tokens of exploration → ~2.9k tokens** with the map.

Savings depend on the task. They are large for "where / what calls this / how does the flow go" questions and small for a one-line fix in a file you already have open.

## What it does

Running `/token` in a project:

1. **Installs graphify** if it's missing: `uv tool install`, then `pipx`, then a private venv in `~/.local/share/token-skill/venv`. No `sudo`.
2. **Builds or updates the map** in `graphify-out/` (AST only). Files with a code extension but an XML body (Tiled tilesets etc.) are added to `.graphifyignore` first, because they break parsing.
3. **Writes a rule** to the project's `CLAUDE.md`, in a marked, idempotent block: for code questions, run `graphify query` before the first grep/read, never `cat` the whole `graph.json`, and update the map after changing code.
4. **Reports real numbers**: nodes/edges, the token size of the report vs. the raw source, and whether the map is stale.

Optional `--strict` mode installs a Claude Code `PreToolUse` hook that blocks the first raw file read in a session until a graph query has run.

## Install

Requirements: macOS, Linux or Windows (Git Bash or WSL), `bash`, Python 3.10+, internet for the first install.

```bash
git clone https://github.com/WebitroHQ/token-skill.git
bash token-skill/token/scripts/install.sh
```

The install copies the skill to `~/.claude/skills/token/` and sets up graphify. The last line should be `ready: type /token in Claude Code`. Then **restart Claude Code**, because skills load at session start.

Check:

```bash
~/.local/bin/graphify --version && ls ~/.claude/skills/token/SKILL.md ~/.claude/skills/graphify/SKILL.md
```

If `graphify` is not found, add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile.

## Usage

In Claude Code, inside a project:

| You say | What happens |
|---|---|
| `/token` | install/verify, build or update the map, write the `CLAUDE.md` rule, report |
| `/token from scratch` | full rebuild (`--force`) |
| `/token strict` | also install the blocking hook |

After that you just ask code questions as usual; the `CLAUDE.md` rule makes Claude query the map first.

The script also works on its own:

```bash
T=~/.claude/skills/token/scripts/token.sh
bash $T status  [path]            # exists? fresh? token summary   (exit 2 = no map, 4 = stale)
bash $T build   [path] [--force]  # build/update the map
bash $T query   "how is auth checked" [path]
bash $T install-project [path] [--strict]
```

## What it writes

- `~/.claude/skills/token/`: this skill
- `~/.claude/skills/graphify/` and a 4-line `# graphify` block at the end of `~/.claude/CLAUDE.md` (added by graphify's own installer)
- `~/.local/bin/graphify` (+ `graphify-mcp`), and `~/.local/share/token-skill/venv` if the venv route was used
- Per project: `graphify-out/` (commit it or add it to `.gitignore`), `.graphifyignore`, and the marked block in `CLAUDE.md`

## Limits

- **Code only.** Docs, PDFs and images need an LLM to map; this skill doesn't run one.
- **Call edges depend on the language.** Tested with graphify 0.9.87: Python and JS/TS get full call edges. Kotlin gets calls inside the same class but misses calls into other objects (e.g. `queue.advance()`). **Dart (Flutter) gets definitions and imports only, no call edges at all**, so "what happens when X runs" questions don't benefit there. The map still tells Claude which file a class or function lives in.
- Some files yield no symbols (plain PHP scripts, config files like `vite.config.ts`). graphify warns about them, and they still need a raw read.
- **The map goes stale** when code changes. `token.sh query` checks this before every query and updates the map first if any code file is newer (seconds on small projects). Tested: rename a function and move its caller to a new file without rebuilding. Before the fix, `graphify query` answered confidently with the old name and old file:line. With the check, the answer comes back with the new name and correct locations. Calling `graphify query` directly skips this check.
- Windows needs Git Bash or WSL; native PowerShell isn't supported.

## Uninstall

```bash
rm -rf ~/.claude/skills/token ~/.local/share/token-skill
uv tool uninstall graphifyy   # or: pipx uninstall graphifyy
```

Then remove the `# >>> token-skill` block from any project `CLAUDE.md` and delete `graphify-out/`.

## Credits

The map itself is [graphify](https://github.com/Graphify-Labs/graphify) (Apache-2.0). This repo is a thin, deterministic wrapper around it for Claude Code, made by [Webitro](https://github.com/WebitroHQ).

## Made by Webitro

[Webitro](https://webitro.com) is a custom software studio. We build AI agents, chatbots, automation and e-commerce systems, and we design custom skills and command sets for teams using Claude Code. If you want a skill tailored to your own workflow, [get in touch](https://webitro.com).

## License

[MIT](LICENSE)
