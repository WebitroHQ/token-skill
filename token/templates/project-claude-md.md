## Project map (token skill — graphify)
`graphify-out/graph.json` in this project is a code map. Goal: don't re-scan the project, spend fewer tokens.
- For code/architecture questions (where is it, what calls it, how does the flow go), BEFORE the first grep/read: `bash ~/.claude/skills/token/scripts/token.sh query "<question>" .` (it updates a stale map first, so answers never point at old names or lines). For a relationship use `graphify path "A" "B"`, for a single concept `graphify explain "X"`. Open raw files only for the lines the query points to. Pass this rule to every sub-agent that explores code.
- NEVER read/cat `graphify-out/graph.json` as a whole (hundreds of thousands of tokens). Use `GRAPH_REPORT.md` only for a high-level architecture overview.
- After changing code: `bash ~/.claude/skills/token/scripts/token.sh update .` (AST, no LLM, seconds). If the map is missing or "STALE", run `update` first.
- If the map looks wrong/incomplete, tell the user; don't silently fall back to raw scanning.
