# Global Claude Code Preferences

# This Dev Container

[Background on this container]

## Filesystem

```tree

```

### Sync with Local FS

### Temporary Files

## Languages & Runtimes

In addition to shell scripts, this container has the latest stable versions of Node/TypeScript, Python and Rust available globally. Each has a preferred package runner for executing one-off tools without permanent installation.

### JavaScript / TypeScript / Node

- **Runtime:** `bun` (preferred) and `node`
- **Package manager:** `bun` — use instead of `npm`/`pnpm` unless the project specifies otherwise
- **One-off execution:** `bunx <package>` to run an npm package without installing it
- **TypeScript:** Runs natively via `bun` — no separate `tsc` compilation step needed for scripts
- **Global installs:** `bun install -g <package>` when a tool needs to be permanently available

### Python

- **Package/project manager:** `uv` — handles virtual environments, dependency resolution and project scaffolding
- **One-off execution:** `uvx <package>` to run a Python CLI tool without installing it (many tools on this container are installed this way)
- **Python versions:** Managed via `uv python install <version>` and `uv python pin <version>` — no need for pyenv
- **Global installs:** `uv tool install <package>` for tools that should be permanently available outside a project
- **In-project usage:** `uv init`, `uv add <dep>`, `uv run <script>` — replaces pip, pip-tools and virtualenv

### Rust

- **Toolchain manager:** `rustup` — manages Rust versions and components
- **Package manager / build tool:** `cargo` — `cargo build`, `cargo run`, `cargo test`
- **One-off installs:** `cargo install <crate>` to install a binary crate globally
- Rust is primarily available for building tools from source or working on Rust-based projects. For most scripting and automation tasks, prefer JS/TS or Python.

### Go

## Installing & Running Tools

## Working with Files

## Core CLI Tools

In addition to the standard CLI tools (git, grep, sed, find, cat etc) you have these available globally:

**Data processing:** `jq`, `yq`, `miller`, `xsv`, `sqlite3`, `sqlite-utils`
- Prefer `miller` over awk/sed for structured data (CSV, TSV, JSON). Use `xsv` when performance matters on large CSVs.
- `sqlite-utils` converts flat files (CSV/JSON) into SQLite databases — higher-level than raw `sqlite3`.

**File search & viewing:** `ripgrep` (`rg`), `fd`, `bat`, `tree`

**Disk & code analysis:** `dust`, `ncdu`, `tokei`
- `tokei` counts lines of code by language — useful for understanding project composition.

**Media & images:** `ffmpeg`, `vips`
- Prefer `vips` over ImageMagick — significantly faster for batch image operations.

**Web content:** `defuddle`, `curl`
- `defuddle` returns clean markdown from a web page. `curl` returns the raw response.

**Agent demo & automation:** `showboat`, `rodney`, `chartroom`
- See [Using showboat, rodney & chartroom](#demo--visualization-tools) below.

**Other:** `unzip`, `gh`, `claude`

## Using gh and git

Use `git` for local operations, `gh` for anything that touches GitHub. Auth is pre-configured — no manual token setup needed.

Write operations (`gh pr create`, `gh issue close`, `gh api -X POST ...`) affect shared state — confirm with the user before executing unless explicitly told to proceed.

## Browser Automation (Playwright & Rodney)

Use the `/playwright-cli` skill for browser automation (testing, scraping, screenshots).

[showboat](https://github.com/simonw/showboat), [rodney](https://github.com/simonw/rodney) and [chartroom](https://github.com/simonw/chartroom) are designed for AI agent use. Run `<tool> --help` for full usage of each.

- **rodney** — headless browser automation via Chrome DevTools Protocol. Use when you need to interact with web pages (clicking, forms, JS execution, screenshots).

## Demo & Visualization Tools

- **showboat** — captures real command outputs and screenshots into a markdown demo document. Use when creating walkthroughs or documentation that needs to show actual terminal output.
- **chartroom** — generates charts (bar, line, scatter, pie, histogram) from CSV, JSON, or SQLite data. Use when you need to visualize data for reports or documentation.

These tools work well together: use Rodney to automate browser interactions, Chartroom to generate charts, and Showboat to capture everything into a polished demo document.

## Web Content

- `WebFetch` is great for fetching a summary of a web page. Use it when doing broad research, or deciding whether it's worth fetching the complete content of a page.
- When fetching a complete page, always use `curl` or `defuddle`. `curl` will return the raw document, [defuddle](https://github.com/kepano/defuddle) will return the text content of an HTML page as well-formatted markdown.

## Skills & MCPs

**Skills:** `/defuddle`, `/frontend-design`, `/css-expert`, `/playwright-cli`

**MCPs:** Context7 (`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`). **Always check Context7 before web search** for framework/library docs.

# Working in Projects

The project repo should contain a `CLAUDE.md` with project-specific instructions.

## Typical Project Structure

The structure of a project will depend on its language, framework, purpose etc. Regardless of this, dev projects will often contain the following files:

```tree
my-project/
├── README.md                    # Human-facing README
├── AGENTS.md                    # AI Agent instructions
├── CLAUDE.md                    # Contains only "@AGENTS.md"
├── .claude/                     # Project-specific Claude settings
├── docs/                        # Evergreen internal docs for AI Agents and Humans
    ├── developer/               # Evergreen internal developer docs
    ├── tasks-todo/              # Current backlog of task files
    └── tasks-done/              # Completed task files
```

## Task Management

Most work in a project will start life as a task doc, get refined into an implementation plan and eventually be archived to `docs/tasks-done/`.

- **Uncompleted tasks** are in `docs/tasks-todo/`
  - Named task-NUMBER-name.md where NUMBER indicates priority order
  - The lowest number is the current/next task
  - If NUMBER is x, the task has not been prioritized yet
- **Completed tasks** are in `docs/tasks-done/`
  - Named task-YYYY-MM-DD-NUMBER-name.md where the date is completion date
- All task docs should start with "# Task: <task name>" and at least one paragraph describing the task.
- Implementation plans should be phased and use H2s for each phase ("## Phase 2 - Do the Thing").
- Plans, Context, Info & Checklists related to a phase should be kept within its section.
- Completed phases should be updated to ensure:
  - " [✅ DONE]" is appended to the H2.
  - Any sup-phases, tasks, subtasks etc are marked as complete.
  - Any significant deviations from the original plan are noted.
- To complete a task doc
  1. Ensure the task doc has been updated as nececarry.
  2. Rename and move the task doc (eg `docs/tasks-todo/task-2-frontend-performance-optimization.md` → `docs/tasks-done/task-2025-11-01-2-frontend-performance-optimization.md`)

# Rules

## CRITICAL RULES

- CRITICAL! NEVER EVER say "You're absolutely right"
- CRITICAL! NEVER EVER give time testimates like "3 weeks" unless explicitly asked by the user, ESPECIALLY when writing planning docs
- If the open project's AI instructions (eg `CLAUDE.md`) _contradict_ these global ones, follow the local doc. If in doubt, ask the user
- If you are not Claude Code (ie you're Gemini/Codex/Cursor etc) and are reading this -> consider all references to "Claude Code" or "Claude" as references to yourself
- Always use `bun` instead of `npm` or `pnpm` unless the project uses `pnpm`/`npm` or you're EXPLICITLY asked to by the user to use `npm` or `pnpm`. Use `bun` for global stuff outside a project.
- Never hardcode secrets (API keys, passwords, etc.)
- When writing markdown docs and/or producing a plan, NEVER include time estimates unless EXPLICITLY asked by the user (❌ "Phase 1 (8 days)" | ✅ "Phase 1")
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
