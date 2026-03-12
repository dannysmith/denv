# Global Claude Code Preferences

[TBD - Background]

## CRITICAL RULES

- CRITICAL! NEVER EVER say "You're absolutely right"
- CRITICAL! NEVER EVER give time testimates like "3 weeks" unless explicitly asked by the user, ESPECIALLY when writing planning docs
- If the open project's AI instructions (eg `CLAUDE.md`) _contradict_ these global ones, follow the local doc. If in doubt, ask the user
- If you are not Claude Code (ie you're Gemini/Codex/Cursor etc) and are reading this -> consider all references to "Claude Code" or "Claude" as references to yourself
- Always use `bun` instead of `npm` or `pnpm` unless the project uses `pnpm`/`npm` or you're EXPLICITLY asked to by the user to use `npm` or `pnpm`. Use `bun` for global stuff outside a project.
- Never hardcode secrets (API keys, passwords, etc.)
- When writing markdown docs and/or producing a plan, NEVER include time estimates unless EXPLICITLY asked by the user (❌ "Phase 1 (8 days)" | ✅ "Phase 1")
- Never run `npm run dev` or `pnpm run dev` or `bun run dev` unless explicitly asked by the user. Instead, ask the user to run it and report back to you.
- Use `gh` CLI for GitHub, `git` for local
- ALWAYS read and understand relevant files before proposing code edits. Do not speculate about code you have not inspected. If the user references a specific file/path, you MUST open and inspect it before explaining or proposing fixes. Be rigorous and persistent in searching code for key facts. Thoroughly review the style, conventions, and abstractions of the codebase before implementing new features or abstractions.

## Other Rules

- Avoid over-engineering. Only make changes that are directly requested or clearly necessary. Keep solutions simple and focused.
- Don't add features, refactor code, or make "improvements" beyond what was asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need extra configurability.
- Don't add error handling, fallbacks, or validation for scenarios that can't happen.
- Don't create helpers, utilities, or abstractions for one-time operations. Don't design for hypothetical future requirements. The right amount of complexity is the minimum needed for the current task. Reuse existing abstractions where possible and follow the DRY principle.
- Always check Context7 before web search for frameworks, languages, tools etc. Only use web search if Context7 lacks info. Be specific in Context7 queries.
- Batch operations when possible and avoid redundant tool calls
- If unsure about a tool, ask user and explain trade-offs

# This Dev Environment

[Explanation of the dev env]

## Pre-configured Languages/Runtimes

### JavaScript/Typescript/Node

### Python

### Rust


## Global CLI Tools

### gh and git

### playwright-cli

### showboat, rodeny & chartroom

- [showboat](https://github.com/simonw/showboat)
- [rodney](https://github.com/simonw/rodney)
- [chartroom](https://github.com/simonw/chartroom)

### Others

- jq
- tree
- ripgrep
- unzip

## Global Claude Skills

[TBD]

- defuddle
- frontend-design
- css-expert

### Globally Available MCPs

- mcp__context7__resolve-library-id
- mcp__context7__query-docs

## Fetching from the web

- `WebFetch` is great for fetching a summary of a web page. Use it when doing broad research, or deciding whether it;s worth fetching the complete content of a page.
- When fetching a complete page, alwayse use `curl` or `defuddle`. `curl` will return the raw document, [defuddle](https://github.com/kepano/defuddle) will return the text content of an HTML page as well-formatted markdown.
