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

This container is pre-configured with Node/TS, Python and Rust.

### JavaScript/Typescript/Node

### Python

### Rust


## Core CLI Tools

In addition to the standard CLI tools (git, grep, sed, find, cat etc) you have these available globally:

- jq
- tree
- ripgrep
- unzip
- gh
- claude
- playwright-cli
- defuddle
- showboat
- rodney
- chartroom
- ffmpeg
- sqlite
- sqlite-utils
- yq
- miller
- xsv
- fd
- bat
- dust and ncdu
- tokei
- vips

### Using gh and git

### Using playwright-cli

### Using showboat, rodeny & chartroom

- [showboat](https://github.com/simonw/showboat)
- [rodney](https://github.com/simonw/rodney)
- [chartroom](https://github.com/simonw/chartroom)

### Fetching from the web

- `WebFetch` is great for fetching a summary of a web page. Use it when doing broad research, or deciding whether it;s worth fetching the complete content of a page.
- When fetching a complete page, alwayse use `curl` or `defuddle`. `curl` will return the raw document, [defuddle](https://github.com/kepano/defuddle) will return the text content of an HTML page as well-formatted markdown.


## Core Skills & MCPs

- defuddle
- frontend-design
- css-expert
- playwright-cli

### Context7 MCP

- mcp__context7__resolve-library-id
- mcp__context7__query-docs

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
