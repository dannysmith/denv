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

- **Toolchain manager:** `rustup` — manages Rust versions and components
- **Package manager / build tool:** `cargo` — `cargo build`, `cargo run`, `cargo test`
- **One-off installs:** `cargo install <crate>` to install a binary crate globally
- Rust is primarily available for building tools from source or working on Rust-based projects. For most scripting and automation tasks, prefer JS/TS or Python.

### Go

- **Runtime:** Go is installed at `/usr/local/go`
- **GOPATH:** `~/go` — `go install` targets end up in `~/go/bin`
- **Installing tools:** `go install <module>@latest` — many developer CLI tools are written in Go
- Go is primarily available for installing tools from source (yq, rodney, etc.) or working on Go projects. For most scripting and automation tasks, prefer JS/TS or Python.

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

You have full `sudo` access. Tools installed via `apt`, `bun -g`, `uv tool`, `cargo install`, or `go install` persist across `denv stop`/`start` but are lost on `denv rebuild`.

## Working with Files

- `rg` (ripgrep) — fast recursive search. Prefer over `grep`.
- `fd` — fast file finder. Prefer over `find`.
- `bat` — cat with syntax highlighting. Aliased to `cat` in this container.
- `tree` — directory tree viewer
- `jq` — JSON processing
- `yq` — YAML/JSON/XML processing (the Go version by Mike Farah, not the Python one)
- `miller` (`mlr`) — structured data processing (CSV, TSV, JSON). Prefer over awk/sed for structured data.
- `sqlite3` — SQLite CLI
- `unzip` — archive extraction
- `ncdu` — interactive disk usage analysis
- `vips` (libvips) — image processing CLI. Prefer over ImageMagick.

## Core CLI Tools

All pre-installed CLI tools beyond the standard set (git, grep, sed, find, etc.):

| Tool | Command | Installed via | Description |
|---|---|---|---|
| ripgrep | `rg` | apt | Fast recursive search (prefer over `grep`) |
| fd | `fd` | apt | Fast file finder (prefer over `find`) |
| bat | `bat` | apt | Cat with syntax highlighting (aliased to `cat`) |
| tree | `tree` | apt | Directory tree viewer |
| jq | `jq` | apt | JSON processor |
| yq | `yq` | go install | YAML/JSON/XML processor (Mike Farah's Go version) |
| miller | `mlr` | apt | Structured data processor (CSV, TSV, JSON) |
| SQLite | `sqlite3` | apt | SQLite CLI |
| ncdu | `ncdu` | apt | Interactive disk usage analyzer |
| libvips | `vips` | apt | Image processing (prefer over ImageMagick) |
| showboat | `showboat` | uv tool | Captures outputs into markdown demo docs |
| chartroom | `chartroom` | uv tool | Generates charts from CSV/JSON/SQLite data |
| rodney | `rodney` | go install | Headless Chrome automation CLI |
| GitHub CLI | `gh` | apt | GitHub operations |
| Claude Code | `claude` | curl installer | AI coding assistant |
| curl | `curl` | apt | HTTP client |
| wget | `wget` | apt | HTTP client |
| unzip | `unzip` | apt | Archive extraction |

## Using gh and git

Use `git` for local operations, `gh` for anything that touches GitHub. Auth is pre-configured via `gh auth git-credential` — no manual token setup needed.

Write operations affect shared state — confirm with the user before executing unless explicitly told to proceed:
- `gh pr create`, `gh pr merge`, `gh pr close`
- `gh issue create`, `gh issue close`
- `gh api -X POST|PUT|DELETE|PATCH ...`
- `git push`, `git push --force-with-lease`

Common read patterns that are always safe:
- `gh repo view`, `gh pr list`, `gh pr view`, `gh issue list`, `gh issue view`
- `gh api /repos/...` (GET requests)
- `gh pr diff`, `gh pr checks`

## Browser Automation (Playwright & Rodney)

This container has Chromium pre-installed and configured for headless-only operation (no display server). Two tools are available:

**Playwright** (via the `/playwright-cli` skill) — full browser automation framework. Use for:
- Multi-step flows (click, fill, navigate, wait)
- Testing (assertions, network interception)
- Waiting for specific selectors or network responses
- Complex scraping with JS rendering

`PLAYWRIGHT_BROWSERS_PATH` and `PLAYWRIGHT_MCP_BROWSER=chromium` are pre-configured. Invoke via the `/playwright-cli` skill.

**Rodney** — simpler headless Chrome CLI for quick tasks. Use for:
- Quick screenshots of a page
- Simple page visits
- Running a JS snippet against a page
- One-off scraping where Playwright is overkill

Run `rodney --help` for full usage.

## Demo & Visualization Tools

**showboat** — captures real command outputs and screenshots into a markdown demo document. Use when creating walkthroughs or documentation that needs to show actual terminal output. Run `showboat --help` for full usage.

**chartroom** — generates charts (bar, line, scatter, pie, histogram) from CSV, JSON, or SQLite data. Use when you need to visualize data for reports or documentation. Run `chartroom --help` for full usage.

These tools work well together: use Rodney to automate browser interactions, Chartroom to generate charts, and Showboat to capture everything into a polished demo document.

## Web Content

- **`WebFetch`** — fetches a summary of a web page. Use for broad research or deciding whether to fetch full content.
- **`curl`** — raw HTTP responses. Use when you need the actual HTML/JSON/etc.
- **`defuddle`** — not installed by default. If needed, install with `bun install -g defuddle-cli`. Extracts clean markdown from HTML pages.

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
