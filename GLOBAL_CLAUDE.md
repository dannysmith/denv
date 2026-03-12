# Global Claude Code Preferences

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

# This Dev Container

[Background on thiscontainer]

## Filesystem

```tree

```

### Sync with local FS

### Temporary Files


## Core Languages & Runtimes

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


## Core CLI Tools

In addition to the standard CLI tools (git, grep, sed, find, cat etc) you have these available globally:

**Data Processing**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `jq` | Query and transform JSON | Parsing API responses, extracting fields from JSON files, reshaping data structures |
| `yq` | Query and transform YAML (and JSON/XML/TOML) | Reading/editing config files, CI pipelines, Kubernetes manifests |
| `miller` | Process structured text (CSV, TSV, JSON) with SQL-like operations | Aggregating, filtering or joining tabular data — like awk but structured-data-aware |
| `xsv` | High-performance CSV toolkit (select, search, join, stats) | Working with large CSV files where `miller` feels slow, or when you need CSV-specific operations like indexing |
| `sqlite3` | SQLite database engine CLI | Querying `.db`/`.sqlite` files, ad-hoc SQL analysis, creating temporary databases |
| `sqlite-utils` | CLI for manipulating SQLite databases and converting data | Inserting CSV/JSON into SQLite, bulk transforms, creating databases from flat files — higher-level than raw `sqlite3` |

**File Search, Viewing & Navigation**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `ripgrep` (`rg`) | Fast recursive text search with regex | Searching file contents across a project — faster than grep and respects `.gitignore` |
| `fd` | Fast file finder with intuitive syntax | Finding files by name/pattern — simpler and faster than `find` |
| `bat` | `cat` with syntax highlighting and line numbers | Viewing file contents when you want syntax highlighting or need to share readable output |
| `tree` | Display directory structure as a tree | Understanding project layout, documenting file hierarchies |

**Disk & Code Analysis**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `dust` | Disk usage analyzer with visual output | Quick overview of what's consuming disk space — like `du` but readable |
| `ncdu` | Interactive disk usage explorer | Drilling down into disk usage interactively when `dust` isn't enough |
| `tokei` | Count lines of code by language | Getting a quick breakdown of a project's language composition and size |

**Media & Images**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `ffmpeg` | Audio/video processing Swiss army knife | Converting formats, extracting audio, trimming clips, generating thumbnails |
| `vips` | High-performance image processing | Resizing, converting, or transforming images — much faster than ImageMagick for batch operations |

**Web Content**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `defuddle` | Extract article text from HTML pages as clean markdown | Fetching the readable content of a web page without clutter — use instead of `curl` when you want just the text |
| `curl` | Transfer data to/from URLs | Fetching raw HTML, calling APIs, downloading files — use when you need the complete unprocessed response |

**Agent Demo & Automation**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `showboat` | Build markdown demo documents with captured command outputs and screenshots | Creating demos, walkthroughs, or documentation that shows real command output |
| `rodney` | Headless browser automation via Chrome DevTools | Automating browser interactions — opening pages, clicking elements, running JS, taking screenshots |
| `chartroom` | Generate charts from tabular data (CSV, JSON, SQLite) | Creating bar/line/scatter/pie charts from data for reports or documentation |

**GitHub & Auth**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `gh` | GitHub CLI — PRs, issues, releases, API access | All GitHub operations — see [Using gh and git](#using-gh-and-git) below |
| `claude` | Claude Code CLI | Spawning sub-agents, running Claude in headless mode |

**General**

| Tool | What it does | When to use |
|------|-------------|-------------|
| `unzip` | Extract ZIP archives | Unpacking downloaded archives |

### Using gh and git

Use `git` for local repository operations (commits, branches, diffs, log) and `gh` for anything that touches GitHub (PRs, issues, releases, API calls).

Auth is pre-configured — `gh` is authenticated and `git` pushes/pulls via `gh`'s credentials. No manual token setup needed.

**Common `gh` patterns:**

- `gh pr create`, `gh pr view`, `gh pr merge` — PR lifecycle
- `gh pr checkout <number>` — check out a PR locally for review or testing
- `gh issue list`, `gh issue create`, `gh issue view` — issue management
- `gh api <endpoint>` — call any GitHub API endpoint directly (e.g. `gh api repos/owner/repo/commits`)
- `gh repo clone <owner/repo>` — clone a repo with auth already configured
- `gh run list`, `gh run view` — check CI/Actions status

**Important:** Read operations (`gh pr view`, `gh api GET ...`) are low-risk. Write operations (`gh pr create`, `gh issue close`, `gh api -X POST ...`) affect shared state — confirm with the user before executing unless you've been explicitly told to proceed.

### Using playwright-cli

Playwright provides browser automation for testing and scraping. It can launch headless Chromium, Firefox, or WebKit browsers to interact with web pages programmatically. For detailed usage and workflows, use the `/playwright-cli` skill which provides comprehensive guidance.

### Using showboat, rodney & chartroom

These three tools ([showboat](https://github.com/simonw/showboat), [rodney](https://github.com/simonw/rodney), [chartroom](https://github.com/simonw/chartroom)) are specifically designed for AI agent use. They're built to be learned via `--help` — run `<tool> --help` to get full usage documentation before first use.

**Showboat** builds markdown demo documents by capturing real command outputs and screenshots. Use it when creating walkthroughs, project demos, or documentation that should show actual terminal output. Typical workflow:

1. `showboat init demo.md "My Demo"` — create a new demo document
2. `showboat note demo.md "Description of what we're about to do"` — add narrative text
3. `showboat exec demo.md bash 'curl ...'` — run a command and embed its output
4. `showboat image demo.md 'screenshot command'` — embed an image
5. `showboat verify demo.md` — re-run the document to verify outputs are still correct

**Rodney** provides headless browser automation via Chrome DevTools Protocol. Use it when you need to interact with web pages — clicking buttons, filling forms, running JavaScript, or taking screenshots. Typical workflow:

1. `rodney start` — launch a headless Chrome instance
2. `rodney open <url>` — navigate to a page
3. `rodney js 'document.title'` — run JavaScript and get results
4. `rodney click 'button.submit'` — click elements by CSS selector
5. `rodney screenshot page.png` — capture the current page
6. `rodney stop` — close the browser

Rodney pairs well with Showboat — use Rodney to automate browser interactions and Showboat to capture the results into a demo document.

**Chartroom** generates charts from data. Use it when you need to visualize CSV, JSON, or SQLite data as bar, line, scatter, pie, or histogram charts. It auto-detects column roles and generates alt text for accessibility.

- `chartroom bar data.csv` — create a bar chart from CSV data
- `chartroom line data.json -x date -y value` — line chart with explicit column mapping
- `chartroom bar --sql mydb.sqlite "SELECT name, count FROM items"` — chart directly from a SQLite query
- Output defaults to `chart.png`; use `-f markdown` or `-f html` for embeddable output

### Fetching from the web

- `WebFetch` is great for fetching a summary of a web page. Use it when doing broad research, or deciding whether it's worth fetching the complete content of a page.
- When fetching a complete page, always use `curl` or `defuddle`. `curl` will return the raw document, [defuddle](https://github.com/kepano/defuddle) will return the text content of an HTML page as well-formatted markdown.


## Core Skills & MCPs

### Skills

| Skill | What it does | When to use |
|-------|-------------|-------------|
| `/defuddle` | Extract clean markdown from web pages using the Defuddle CLI | When you need to read the content of a URL — cleaner and more token-efficient than `WebFetch` for full-page reads |
| `/frontend-design` | Generate distinctive, production-grade frontend UI with high design quality | When building web components, pages, or applications — produces polished, non-generic code |
| `/css-expert` | Expert guidance on modern CSS (cascade layers, OKLCH, container queries, defensive patterns) | CSS implementation, styling, layout, responsive design, and UI component work |
| `/playwright-cli` | Browser automation for testing and scraping via Playwright | When you need to test web UIs, take screenshots of running apps, or scrape dynamic pages |

### MCPs

| MCP Tool | What it does | When to use |
|----------|-------------|-------------|
| `mcp__context7__resolve-library-id` | Resolve a library name to its Context7 ID | First step before querying docs — pass a library name (e.g. "react", "fastapi") to get the ID |
| `mcp__context7__query-docs` | Query up-to-date documentation for a library | Look up API references, usage patterns, or examples for any framework/library — **always check here before web search** |

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
