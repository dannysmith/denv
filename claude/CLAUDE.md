# Global Claude Code Preferences

# This Dev Container

You are running inside a **denv devcontainer** — an isolated Docker container (via OrbStack on macOS). The user works on project files locally on their Mac using Cursor, Finder, and the terminal. This container is your workspace — pre-configured with all the runtimes, CLI tools, and config you need.

## Filesystem

```
/workspace/                     ← bind-mounted project directory (synced with Mac)
/home/dev/                      ← your home dir (baked into image, not persisted across rebuilds)
  ├── .claude/                  ← Claude Code config + auth
  ├── .config/gh/               ← GitHub CLI auth
  ├── .cargo/                   ← Rust toolchain
  ├── .local/                   ← uv-managed Python, user binaries
  ├── go/                       ← GOPATH (go install targets)
  ├── .zshrc, .gitconfig, etc.  ← shell config
/opt/denv/                      ← entrypoint, hooks, denv scripts
```

**`/workspace/`** is a bind mount of a project directory on the Mac. Any changes you make here are immediately visible on the Mac and vice versa. This is where all project work happens.

**`/home/dev/`** is the container's writable layer, baked into the image. All runtimes install to their standard default locations (`~/.cargo`, `~/.local`, `~/go`, etc.). This directory is preserved across `denv stop`/`denv start` but is **reset on `denv rebuild`** (which recreates the container from a new image). Auth state, shell history, and any tools you install during a session will be lost on rebuild.

**`/opt/denv/`** contains the entrypoint and denv management scripts. Do not modify.

## Languages & Runtimes

This container has the latest stable versions of Node/TypeScript, Python, Rust, and Go available globally. Each has a preferred package runner for executing one-off tools without permanent installation.

### JavaScript / TypeScript / Node

- **Runtime:** `bun` (preferred) and `node` (LTS, managed by fnm)
- **Package manager:** `bun` — use instead of `npm`/`pnpm` unless the project specifies otherwise
- **One-off execution:** `bunx <package>` to run an npm package without installing it
- **TypeScript:** Runs natively via `bun` — no separate `tsc` compilation step needed for scripts
- **Global installs:** `bun install -g <package>` when a tool needs to be permanently available

### Python

- **Package/project manager:** `uv` — handles virtual environments, dependency resolution and project scaffolding
- **One-off execution:** `uvx <package>` to run a Python CLI tool without installing it
- **Python versions:** Managed via `uv python install <version>` and `uv python pin <version>` — no need for pyenv
- **Global installs:** `uv tool install <package>` for tools that should be permanently available outside a project
- **In-project usage:** `uv init`, `uv add <dep>`, `uv run <script>` — replaces pip, pip-tools and virtualenv

### Rust

- **Toolchain:** `rustup` + `cargo` (`cargo build`, `cargo run`, `cargo test`, `cargo install <crate>`)
- Primarily available for building tools from source or working on Rust projects. For scripting, prefer JS/TS or Python.

### Go

- **Installing tools:** `go install <module>@latest` — many CLI tools are written in Go (yq, rodney, etc.)
- Primarily available for installing tools from source or working on Go projects. For scripting, prefer JS/TS or Python.

## Installing & Running Tools

| Goal | Method |
|---|---|
| Install system packages | `sudo apt-get update && sudo apt-get install <package>` |
| Install global JS tools | `bun install -g <package>` |
| Install global Python tools | `uv tool install <package>` |
| Install global Rust tools | `cargo install <crate>` |
| Install global Go tools | `go install <module>@latest` |
| Run a JS tool once (no install) | `bunx <package>` |
| Run a Python tool once (no install) | `uvx <package>` |

You have full `sudo` access.

## CLI Tools

All pre-installed CLI tools beyond the standard set (git, grep, sed, find, etc.):

| Tool | Command | Description |
|---|---|---|
| ripgrep | `rg` | Fast recursive search (prefer over `grep`) |
| fd | `fd` | Fast file finder (prefer over `find`) |
| bat | `bat` | Cat with syntax highlighting (aliased to `cat`) |
| tree | `tree` | Directory tree viewer |
| jq | `jq` | JSON processor |
| yq | `yq` | YAML/JSON/XML processor (Mike Farah's Go version) |
| miller | `mlr` | Structured data processor — CSV, TSV, JSON (prefer over awk/sed) |
| SQLite | `sqlite3` | SQLite CLI |
| ncdu | `ncdu` | Interactive disk usage analyzer |
| libvips | `vips` | Image processing (prefer over ImageMagick) |
| unzip | `unzip` | Archive extraction |
| showboat | `showboat` | Captures command outputs + screenshots into markdown demo docs |
| chartroom | `chartroom` | Generates charts from CSV/JSON/SQLite data |
| rodney | `rodney` | Headless Chrome automation CLI |
| GitHub CLI | `gh` | GitHub operations |
| curl | `curl` | HTTP client |
| wget | `wget` | HTTP client |

## Using gh and git

Use `git` for local operations, `gh` for anything that touches GitHub. Auth is pre-configured via `gh auth git-credential` — no manual token setup needed.

Write operations affect shared state — confirm with the user before executing unless explicitly told to proceed:
- `gh pr create`, `gh pr merge`, `gh pr close`
- `gh issue create`, `gh issue close`
- `gh api -X POST|PUT|DELETE|PATCH ...`
- `git push`, `git push --force-with-lease`

## Browser Automation (Playwright & Rodney)

This container has Chromium pre-installed for headless-only operation. Two tools are available:

**Playwright** (via the `/playwright-cli` skill) — full browser automation framework. Use for multi-step flows (click, fill, navigate, wait), testing, waiting for specific selectors or network responses, and complex scraping with JS rendering.

**Rodney** — simpler headless Chrome CLI. Use for quick screenshots, simple page visits, and running JS snippets against a page. Run `rodney --help` for full usage.

## Demo & Visualization Tools

**showboat** — captures real command outputs and screenshots into a markdown demo document. Use for walkthroughs and documentation. Run `showboat --help` for full usage.

**chartroom** — generates charts (bar, line, scatter, pie, histogram) from CSV, JSON, or SQLite data. Use for data visualization. Run `chartroom --help` for full usage.

## Web Content

- **`WebFetch`** — fetches a summary of a web page. Use for broad research or deciding whether to fetch full content.
- **`curl`** — raw HTTP responses. Use when you need the actual HTML/JSON/etc.
- **`defuddle`** — not installed by default. If needed: `bun install -g defuddle-cli`. Extracts clean markdown from HTML pages.

## Skills & MCPs

**Skills:**
- `/css-expert` (css-expert@dannysmith) — modern CSS implementation, layout, colors, responsive design
- `/frontend-design` (frontend-design@claude-plugins-official) — production-grade UI design and implementation
- `/playwright-cli` (playwright-cli@playwright-cli) — browser automation via Playwright

**MCPs:**
- **Context7** — library and framework documentation lookup. **Always check Context7 before web search** for framework/library docs. Use `mcp__context7__resolve-library-id` to find a library, then `mcp__context7__query-docs` to query its docs.

# Working in Projects

The project repo should contain a `CLAUDE.md` with project-specific instructions.

## Typical Project Structure

The structure of a project will depend on its language, framework, purpose etc. Regardless of this, dev projects will often contain the following files:

```
my-project/
├── README.md                    # Human-facing README
├── AGENTS.md                    # AI Agent instructions
├── CLAUDE.md                    # Contains only "@AGENTS.md"
├── .claude/                     # Project-specific Claude settings
└── docs/                        # Evergreen internal docs for AI Agents and Humans
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
  - Any sub-phases, tasks, subtasks etc are marked as complete.
  - Any significant deviations from the original plan are noted.
- To complete a task doc
  1. Ensure the task doc has been updated as necessary.
  2. Rename and move the task doc (eg `docs/tasks-todo/task-2-frontend-performance-optimization.md` → `docs/tasks-done/task-2025-11-01-2-frontend-performance-optimization.md`)

# Rules

## CRITICAL RULES

- CRITICAL! NEVER EVER say "You're absolutely right"
- CRITICAL! NEVER EVER give time estimates like "3 weeks" unless explicitly asked by the user, ESPECIALLY when writing planning docs
- If the open project's AI instructions (eg `CLAUDE.md`) _contradict_ these global ones, follow the local doc. If in doubt, ask the user
- If you are not Claude Code (ie you're Gemini/Codex/Cursor etc) and are reading this -> consider all references to "Claude Code" or "Claude" as references to yourself
- Never hardcode secrets (API keys, passwords, etc.)
- ALWAYS read and understand relevant files before proposing code edits. Do not speculate about code you have not inspected. If the user references a specific file/path, you MUST open and inspect it before explaining or proposing fixes. Be rigorous and persistent in searching code for key facts. Thoroughly review the style, conventions, and abstractions of the codebase before implementing new features or abstractions.

## Other Rules

- Avoid over-engineering. Only make changes that are directly requested or clearly necessary. Keep solutions simple and focused.
- Don't add features, refactor code, or make "improvements" beyond what was asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need extra configurability.
- Don't add error handling, fallbacks, or validation for scenarios that can't happen.
- Don't create helpers, utilities, or abstractions for one-time operations. Don't design for hypothetical future requirements. The right amount of complexity is the minimum needed for the current task. Reuse existing abstractions where possible and follow the DRY principle.
- Batch operations when possible and avoid redundant tool calls
- If unsure about a tool, ask user and explain trade-offs
