# Task: Claude Code Customisation

Configure Claude Code inside the container with the right global instructions, settings, plugins, skills, and MCPs. After this phase, creating a new denv container should result in a fully configured Claude Code environment with all the tools and context it needs.

## Phase 1: CLAUDE.md (Global Instructions)

### Goal

Create `claude/CLAUDE.md` — the global instructions file baked into the container image at `/home/dev/.claude/CLAUDE.md`. This replaces the current `GLOBAL_CLAUDE.md` draft. It should give Claude Code complete context about its environment, tools, and how to use them.

### Structure

The file should contain the following sections, in this order:

**1. Container Environment**
- Brief explanation: you're in a denv devcontainer (Docker via OrbStack on macOS)
- `/workspace/` is bind-mounted from the Mac — edits are live on both sides
- `/home/dev/` is the container's home dir, baked into the image (not persisted across rebuilds)
- Make it clear: if Claude Code is reading this file, it's running inside the container

**2. Languages & Runtimes**
Keep roughly the same structure as the existing `GLOBAL_CLAUDE.md` sections for:
- Node/Bun (fnm, bun preferred over npm, bunx for one-off execution, TypeScript via bun)
- Python/uv (uv for everything, uvx for one-off, uv tool install for persistent global)
- Rust/Cargo (rustup, cargo, cargo install)
- Go (go install for tools)

**3. Installing & Running Tools**
A clear section explaining how to install things globally and how to run things without installing:

| Goal | Method |
|---|---|
| Install system packages | `sudo apt-get install` |
| Install global JS tools | `bun install -g <package>` |
| Install global Python tools | `uv tool install <package>` |
| Install global Rust tools | `cargo install <crate>` |
| Install global Go tools | `go install <module>@latest` |
| Run a JS tool once | `bunx <package>` |
| Run a Python tool once | `uvx <package>` |

**4. Working with Files**
Bulleted list of file-related CLI tools available, with brief notes on preferences:
- `rg` (ripgrep) — prefer over grep
- `fd` — prefer over find
- `bat` — cat with syntax highlighting (aliased to `cat`)
- `tree` — directory tree viewer
- `jq` / `yq` — JSON / YAML processing
- `miller` — structured data (CSV, TSV, JSON). Prefer over awk/sed for structured data
- `sqlite3` — SQLite CLI
- `unzip` — archive extraction
- `ncdu` — disk usage analysis
- `libvips` (`vips`) — image processing. Prefer over ImageMagick

**5. Core CLI Tools Table**
Table format covering all pre-installed CLI tools:

| Tool | Command | Description |
|---|---|---|
| ripgrep | `rg` | Fast recursive grep |
| fd | `fd` | Fast file finder |
| bat | `bat` | Cat with syntax highlighting |
| tree | `tree` | Directory tree viewer |
| etc... | | |

**6. Using gh and git**
- Use `git` for local, `gh` for GitHub
- Auth is pre-configured (credential helper via `gh`)
- Write operations (`gh pr create`, `gh issue close`, `gh api -X POST`) affect shared state — confirm with the user before executing unless explicitly told to proceed
- Common patterns: `gh repo view --web`, `gh pr list`, `gh pr create`, `gh api`

**7. Browser Automation (Playwright & Rodney)**
- **Playwright** via the `/playwright-cli` skill — full browser automation (testing, scraping, form filling, screenshots)
- Headless-only in the container (no display server)
- `PLAYWRIGHT_BROWSERS_PATH` and `PLAYWRIGHT_MCP_BROWSER=chromium` are pre-configured
- **Rodney** — simpler headless Chrome CLI for quick automation tasks (visit page, screenshot, run JS)
- When to use Playwright vs Rodney:
  - Playwright: multi-step flows, form filling, testing, waiting for network/selectors
  - Rodney: quick screenshots, simple page visits, running JS snippets

**8. Demo & Visualization Tools**
- **showboat** — captures command outputs and screenshots into markdown demo docs. Use for walkthroughs and documentation.
- **chartroom** — generates charts (bar, line, scatter, pie, histogram) from CSV, JSON, or SQLite data. Use for data visualization.
- These work well together and with Rodney for browser-based demos
- Run `<tool> --help` for full usage

**9. Web Content**
- `WebFetch` — for summaries/broad research
- `curl` — raw responses
- `defuddle` — currently **not installed**, would need `bun install -g defuddle-cli` if needed. Extracts clean markdown from web pages.

**10. Skills & MCPs**
List of available default skills:
- `/css-expert` (css-expert@dannysmith) — modern CSS implementation
- `/frontend-design` (frontend-design@claude-plugins-official) — production-grade UI design
- `/playwright-cli` (playwright-cli@playwright-cli) — browser automation

MCP servers:
- **Context7** — library documentation lookup. Always check Context7 before web search for framework/library docs. Use `mcp__context7__resolve-library-id` → `mcp__context7__query-docs`.

**11. Working in Projects** (keep as-is from GLOBAL_CLAUDE.md)
- Typical project structure
- Task management conventions

**12. Critical Rules / Other Rules** (keep as-is from GLOBAL_CLAUDE.md)

### What to Build

- Create `claude/CLAUDE.md` with the above content
- Audit every tool reference against the Dockerfile to ensure accuracy (don't list tools we haven't installed)
- Remove references to tools not in the image (xsv, sqlite-utils, dust, tokei, ffmpeg, defuddle CLI)
- Update Dockerfile to `COPY --chown=dev:dev claude/CLAUDE.md /home/dev/.claude/CLAUDE.md`

### How to Verify

1. Rebuild image, create test container
2. Start Claude session — verify CLAUDE.md is loaded
3. Ask Claude what tools are available — should match the doc
4. Ask Claude to use Context7 — should work
5. Try a skill invocation (e.g. `/css-expert`) — should work

---

## Phase 2: Claude Settings & Config Files

### Goal

Create the remaining configuration files in `claude/` that get baked into the image.

### What to Build

**`claude/settings.json`** — user-level settings for the container:
- Permissive `allow` list (this is Claude's sandbox — let it do things)
- Broad allows: all Read, Glob, Grep, Edit, Write, Bash commands for local work
- `enabledPlugins` for the plugins we install (Phase 3)
- No deny list for now (Phase 5 will add write-gating)
- `alwaysThinkingEnabled: true`

**`claude/.claude.json`** — user-level MCP config:
- Context7 MCP server: `{"mcpServers": {"context7": {"type": "stdio", "command": "npx", "args": ["-y", "@upstash/context7-mcp"]}}}`

### Dockerfile Updates

```dockerfile
COPY --chown=dev:dev claude/CLAUDE.md /home/dev/.claude/CLAUDE.md
COPY --chown=dev:dev claude/settings.json /home/dev/.claude/settings.json
COPY --chown=dev:dev claude/.claude.json /home/dev/.claude.json
```

Note: `.claude.json` goes to `/home/dev/.claude.json` (not inside `.claude/`) — this is where Claude Code reads user-level MCP config.

### How to Verify

1. Rebuild image, create test container
2. Check files are in the right places with correct ownership
3. Start Claude session, verify settings are applied
4. Verify Context7 MCP is available (ask Claude to look up docs for a library)

---

## Phase 3: Plugin & Skill Installation Script

### Goal

Create a reusable script that installs/updates the standard set of Claude Code plugins and skills in any denv container. This avoids baking plugins into the image (which would require rebuilds to update) and allows updating all existing containers by re-running the script.

### Design

**`scripts/install-claude-plugins.sh`** — runs inside a container (requires Claude auth):

```bash
#!/usr/bin/env bash
# Install/update the standard denv Claude Code plugin set
# Requires: claude auth login to have been completed

set -euo pipefail

# Add custom marketplaces (idempotent — skip if already present)
claude plugin marketplace add dannysmith/claude-marketplace 2>/dev/null || true
claude plugin marketplace add microsoft/playwright-cli 2>/dev/null || true
# claude-plugins-official is built-in

# Install/update plugins
claude plugin install css-expert@dannysmith
claude plugin install frontend-design@claude-plugins-official
claude plugin install playwright-cli@playwright-cli

echo "Claude plugins installed successfully."
```

**Key points:**
- The script is copied into the image at `/opt/denv/install-claude-plugins.sh`
- It can be run manually inside any container: `/opt/denv/install-claude-plugins.sh`
- `denv create` runs it automatically after auth (Phase 4)
- To update plugins across all containers, run `denv exec-all /opt/denv/install-claude-plugins.sh` or just re-run it in each container
- Adding a new plugin = add a line to the script + re-run in each container (or on next rebuild)

**Updating plugins in existing containers from the Mac:**
- Add a `denv update-plugins [project]` command that copies the latest script from the repo into the container and runs it
- Or: `denv exec <project> /opt/denv/install-claude-plugins.sh` (simpler, but uses the script baked into the image)

### Open Questions

- Do `claude plugin install` / `claude plugin marketplace add` require authentication? If so, the script can only run after `claude auth login`. Need to verify this during implementation.
- Are marketplace add and plugin install idempotent (safe to re-run)?
- Does `claude plugin install` update an existing plugin or do we need `claude plugin update` separately?

### How to Verify

1. Shell into a container, run `claude auth login`
2. Run `/opt/denv/install-claude-plugins.sh`
3. Start Claude session, verify all skills are available
4. Re-run the script — should be idempotent (no errors, no duplicates)

---

## Phase 4: Better `denv create`

### Goal

Make `denv create` a one-shot command that creates a fully configured container — including auth and plugin setup. The user should only need to interact for browser-based authentication steps.

### Flow

```
$ denv create ~/dev/my-project
  1. Create container (existing docker run logic)
  2. Shell in and run: gh auth login --hostname github.com --git-protocol https --web
     → User clicks link, authenticates in browser
  3. Run: claude auth login
     → User clicks link, authenticates in browser
  4. Run: /opt/denv/install-claude-plugins.sh
     → Installs plugins (now that auth is done)
  5. Print success message with next steps
```

### What to Build

**Update `denv create`**:

After the `docker run` step, exec into the container and run the auth + setup sequence:

```bash
# Step 1: GitHub auth (web-based, non-interactive except for browser)
docker exec -it "$container" gh auth login \
    --hostname github.com \
    --git-protocol https \
    --web \
    --skip-ssh-key

# Step 2: Claude auth
docker exec -it "$container" claude auth login

# Step 3: Install plugins
docker exec "$container" /opt/denv/install-claude-plugins.sh
```

Each step requires `-it` (interactive terminal) for the auth flows but the user just needs to click a link and authenticate in their browser.

**Add `denv update-plugins [project]`**:

Copies the latest `install-claude-plugins.sh` from the denv repo into the container and runs it. This allows updating plugins without rebuilding:

```bash
cmd_update_plugins() {
    local project="${1:?Usage: denv update-plugins <project>}"
    local container=$(container_name "$project")
    # Copy latest script from repo
    docker cp "$DENV_DIR/scripts/install-claude-plugins.sh" \
        "$container:/opt/denv/install-claude-plugins.sh"
    # Run it
    docker exec "$container" /opt/denv/install-claude-plugins.sh
}
```

### How to Verify

1. `denv create ~/dev/test-project` — should prompt for GH auth, then Claude auth, then install plugins
2. Shell in, start Claude — all skills and MCPs should work
3. Add a new plugin to `install-claude-plugins.sh`
4. `denv update-plugins test-project` — should install the new plugin without rebuild
5. Verify the new skill is available in Claude

---

## Notes

### Plugin System Dependencies

The plugin installation approach depends on:
- `claude plugin install` and `claude plugin marketplace add` being stable CLI commands
- These commands being usable non-interactively (after auth)
- Marketplace add being idempotent

If any of these assumptions fail during implementation, fall back to Option C from the original plan (clone marketplace repos during image build and configure cache/manifests directly).

### What's NOT in This Task

- Write-gating / permission lockdown (Phase 5 in main plan)
- The `denv scaffold` command (Phase 4 in main plan)
- Personal plugins (personal@dannysmith, writing@dannysmith, obsidian@obsidian-skills, tdn@tdn-marketplace) — these are Mac-specific and not needed in the container. Can be added to the install script later if needed.
