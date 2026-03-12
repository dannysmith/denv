# Ring-Fenced Development Environment

## Overview

This project creates isolated Docker containers (managed via OrbStack on macOS) where Claude Code can run with near-full autonomy. Project files are bind-mounted from the Mac, so the user works on them locally in Cursor, Finder, and the terminal as normal. The container is primarily "Claude's workspace" — pre-configured with all the tools Claude Code needs to operate effectively.

The core problem: on a bare Mac, giving Claude Code broad permissions risks accidental damage to the host filesystem and potential data exfiltration. The solution: run Claude Code inside a container where it can do anything it wants, while gating operations that write to external services (git push, gh api POST, etc.).

A CLI tool called `denv` manages the lifecycle of these containers.

## Architecture

### Container Model

```
Mac (host)
├── ~/dev/my-project/          ← you edit files here (Cursor, terminal, Finder)
│   ├── src/
│   ├── package.json
│   └── ...
│
└── Docker container (via OrbStack)
    ├── /workspace/            ← bind mount of ~/dev/my-project (same files)
    ├── /home/dev/             ← named volume (persists across rebuilds)
    │   ├── .claude/           ← Claude auth + runtime state
    │   ├── .config/gh/        ← GitHub CLI auth
    │   ├── .zshrc             ← shell config (synced from image on rebuild)
    │   └── ...
    └── (system)               ← from base image (runtimes, CLI tools, etc.)
```

All project containers share a single base Docker image (`denv-base`). The image contains all runtimes, CLI tools, shell config, and Claude Code configuration. Disk layers are shared via overlay2. Read-only files (binaries, libraries) share page cache in RAM across containers.

### Volume & Persistence Model

Each container has exactly **two mounts**:

1. **Bind mount**: project directory from Mac → `/workspace` in container
2. **Named volume**: `denv-<project>-home` → `/home/dev` (the user's entire home directory inside the container)

The home volume captures everything: Claude auth, gh auth, shell history, globally-installed user-space tools (`~/.local/bin`, `~/.cargo/bin`, `~/.bun/bin`, etc.), and any scratch files Claude creates in `~/`.

**First-run behaviour**: When a named volume is first mounted to a path that has contents in the image, Docker populates the volume from the image. So the first `denv create` gets dotfiles, Claude config, etc. from the base image automatically.

**After base image rebuild**: The volume already has data, so image updates to `/home/dev` are ignored. An entrypoint script handles this: it checks a version stamp in the volume against the image version and syncs template files (dotfiles, Claude config) while preserving user state (auth credentials, shell history, installed tools).

**Persistence by scenario**:

| Scenario | Project files | Home dir (auth, tools, history) | System (apt packages, global bins) |
|---|---|---|---|
| `denv stop` / `denv start` | Safe (on Mac) | Preserved | Preserved |
| `denv rebuild` (new base image) | Safe (on Mac) | Preserved (volume) | Reset to new image |
| `denv rm` | Safe (on Mac) | Gone (unless `--keep-volumes`) | Gone |

### Filesystem Layout (inside container)

```
/workspace/                     ← bind-mounted project directory
/home/dev/                      ← named volume (persistent home)
  ├── .claude/                  ← Claude Code config + auth
  ├── .config/gh/               ← GitHub CLI auth
  ├── .zshrc, .gitconfig, etc.  ← shell config
  ├── .local/bin/               ← user-installed binaries
  └── .denv-version             ← version stamp for entrypoint sync
/opt/denv/                      ← image-baked templates (source of truth for syncing)
  ├── home-template/            ← dotfiles, Claude config
  └── hooks/                    ← write-gating hooks
```

### Networking

OrbStack automatically forwards ports from Docker containers to `localhost` on the Mac. When Claude starts a dev server on port 3000 inside the container, it is accessible at `localhost:3000` in the Mac browser. No explicit port mapping needed.

### Container Naming

- Container: `denv-<project-name>` (where project-name is the directory name from the path given to `denv create`)
- Volume: `denv-<project-name>-home`

### Dependency Directories (node_modules, etc.)

Project-level dependency directories (`node_modules`, `venv`, `target`, etc.) live inside the bind-mounted project directory. Both the container and the Mac see them. No special volume treatment. OrbStack's VirtioFS bind mount performance is ~80-95% of native, which is acceptable. This keeps things simple and means you can run/build both inside the container and locally on the Mac.

### Image Sharing with Claude Code

Clipboard image paste does not work in container terminals. The practical workaround is a keyboard shortcut on the Mac that saves the clipboard to a known path accessible from the container (via the bind mount or a shared location). Implementation details deferred — not a critical-path feature.

---

## Phase 1: Base Repo & Dockerfile

### Goal

Get a working Docker container that can run Claude Code against a bind-mounted project, with the correct volume setup. Verify the fundamental workflow: Claude works inside the container while the user edits files locally.

### What to Build

**Repo structure** (initial):
```
denv/
├── Dockerfile
├── scripts/
│   └── entrypoint.sh
└── .gitignore
```

**Dockerfile** — minimal but functional:
- `FROM ubuntu:24.04`
- Install: `git`, `curl`, `zsh`, `sudo`, `ca-certificates`, `jq`, basic build tools
- Install Node.js (via fnm or direct) + Bun
- Install Claude Code (`curl -fsSL https://claude.ai/install.sh | bash`)
- Install GitHub CLI (`gh`)
- Create non-root user `dev` with sudo access and zsh as default shell
- Set `WORKDIR /workspace`

**entrypoint.sh** — minimal:
- Ensure correct ownership of `/home/dev` volume
- Exec into zsh (or whatever command was passed)

**Volume setup**: bind mount for project dir, named volume for home.

### How to Verify

1. Build the image: `docker build -t denv-base .`
2. Create a test project: `mkdir ~/dev/test-project && cd ~/dev/test-project && git init && echo "# Test" > README.md`
3. Run container manually: `docker run -it --name denv-test-project -v ~/dev/test-project:/workspace -v denv-test-project-home:/home/dev denv-base`
4. Inside container: run `claude --version`, `gh --version`, `git status`
5. Inside container: run `gh auth login` and `claude /login`, verify auth works
6. Inside container: start a Claude session, ask it to create a file
7. On Mac: verify the file appears in `~/dev/test-project/`
8. On Mac: edit a file in Cursor, verify the change is visible inside the container
9. Open `~/dev/test-project/` in Cursor — verify normal local editing works
10. `docker stop` / `docker start` — verify home dir state persists

---

## Phase 2: Dotfiles & Dev Tools

### Goal

Flesh out the base image with all required runtimes, CLI tools, and a sensible shell configuration. After this phase, shelling into a container should feel productive.

### What to Build

**Update Dockerfile** with full tool list:

Runtimes:
- Node.js (latest stable via fnm) + Bun/bunx
- Python (latest stable) + uv/uvx
- Rust (via rustup, cargo)

CLI tools:
- Already from Phase 1: git, gh, claude, curl, jq
- Add: ripgrep, fd, bat, tree, unzip, ffmpeg, sqlite3, yq, miller, xsv, dust, ncdu, tokei, vips (libvips-tools)
- Via bun/bunx: defuddle, @playwright/cli@latest
- Via cargo: xsv, dust, tokei (if not available via apt — check availability)
- Via pip/uv: sqlite-utils
- Simon Willison's tools: showboat, rodney, chartroom (check install methods — likely pip/uv or bun)
- Playwright - may need installing in addition to the playwright/cli along with Chromium?
- 
**Create dotfiles** (`dotfiles/` in repo):
- `zshrc` — minimal but functional: prompt, basic aliases (`g`=git, etc.), PATH setup for all installed runtimes, fnm init, cargo env, bun paths
- `gitconfig` — sensible defaults (pull rebase, verbose commits, `gh auth git-credential` for HTTPS auth, colors)
- `gitignore_global` — standard ignores (OS files, editor files, env files, *.local and *.local.*)

**Update entrypoint.sh** with version-stamp sync logic:
- Bake dotfiles and config into `/opt/denv/home-template/` in the image
- On container start, compare `/home/dev/.denv-version` with image version
- If missing or outdated: copy template dotfiles into `/home/dev/`, update version stamp
- Never overwrite: `.claude/` auth state, `.config/gh/` auth, `.zsh_history`, `.local/`, `.cargo/`, `.bun/`

**Create minimal `denv` script** (just enough for testing):
- `denv create <path>` — runs `docker run` with correct mounts and naming
- `denv shell <project>` — runs `docker exec -it` into existing container
- Add to PATH or symlink for convenience

### How to Verify

1. Rebuild image, recreate test container via `denv create ~/dev/test-project`
2. `denv shell test-project`
3. Verify all tools are available: `node --version`, `bun --version`, `python --version`, `rustc --version`, `uv --version`, `rg --version`, `fd --version`, `bat --version`, etc.
4. Verify shell feels right: prompt works, aliases work, tab completion works
5. Verify entrypoint sync: rebuild image with a dotfile change, restart container, confirm the change is picked up without losing auth state

---

## Phase 3: Claude Code Customisation

### Goal

Configure Claude Code inside the container with the right global instructions, settings, plugins, skills, and MCPs. After this phase, starting Claude in a container should have all the tools and context it needs.

### What to Build

**Claude config** (`claude/` in repo):
- `CLAUDE.md` — global instructions for the container environment. Based on `GLOBAL_CLAUDE.md` but completed. Key contents:
- `settings.json` — initial permissive settings (will be refined in Phase 5). For now: broad allow list, minimal deny list.

**Plugin/skill/MCP installation**:
- Determine how Claude Code plugins and skills are installed non-interactively (via CLI commands, config files, or file placement)
- Bake plugin/skill installation into the Dockerfile or entrypoint
- Required: defuddle skill, frontend-design skill, css-expert skill
- Required MCP: Context7 (runs via `npx -y @upstash/context7-mcp`)

**Update Dockerfile**:
- Copy Claude config into `/opt/denv/home-template/.claude/`
- Ensure entrypoint syncs Claude config (CLAUDE.md, settings.json, hooks) on version mismatch but preserves auth/session state

### How to Verify

1. Rebuild image, recreate container
2. Start Claude session inside container
3. Verify Claude knows about the environment (ask it what tools are available)
4. Verify Context7 MCP works (ask Claude to look up docs for a library)
5. Verify skills are available (try invoking defuddle, css-expert)
6. Verify settings are applied (check `/home/dev/.claude/settings.json`)

---

## Phase 4: Complete the `denv` CLI

### Goal

Build the full `denv` CLI tool that manages the complete container lifecycle from the Mac.

### What to Build

**`denv`** — a shell script (bash or zsh) providing:

| Command | Description |
|---|---|
| `denv create <path>` | Create a new container for the project at `<path>`. Uses directory name as project name. Builds image if needed. |
| `denv <project>` | Shortcut for `denv shell <project>` |
| `denv shell <project>` | Open a zsh shell inside the container (starts it first if stopped) |
| `denv claude <project> [args]` | Run `claude` inside the container, passing any extra args |
| `denv start <project>` | Start a stopped container |
| `denv stop <project>` | Stop a running container |
| `denv rm <project> [--volumes]` | Remove container. `--volumes` also removes the home volume. |
| `denv rebuild [project]` | Rebuild base image. If project specified, recreate that container (preserving volumes). |
| `denv ls` | List all denv containers with status (running/stopped) |
| `denv scaffold <name> [path]` | Create a new project directory at `<path>/<name>` (default `~/dev/<name>`), populate with template files, `git init`, then `denv create`. |

**Scaffold templates** (`scaffold/` in repo):
- `README.md` — minimal project readme
- `AGENTS.md` — Basic project instructions
- `CLAUDE.md` - Just "@AGENTS.md"
- `.gitignore` — sensible defaults
- `docs/tasks-todo/.gitkep`
- `docs/tasks-done/.gitkep`

**Installation**: the script lives in the repo. User symlinks it to somewhere on PATH (e.g., `ln -s ~/dev/denv/denv ~/.local/bin/denv`).

### Design Notes

- `denv create` should check if a container already exists and warn/skip
- `denv shell` and `denv claude` should auto-start a stopped container before exec-ing
- `denv rebuild` should: rebuild the image, stop the container, remove it (keeping volumes), create a new container from the new image with the same mounts
- `denv ls` should show: project name, container status, project path
- Error messages should be clear and suggest the right command

### How to Verify

1. `denv create ~/dev/test-project` — creates container
2. `denv ls` — shows the container
3. `denv test-project` — opens shell
4. `denv claude test-project` — starts Claude session
5. `denv stop test-project` / `denv start test-project` — lifecycle works
6. `denv rebuild test-project` — new image, state preserved
7. `denv scaffold new-idea` — creates `~/dev/new-idea/` with template files and a container
8. `denv rm test-project --volumes` — cleans up

---

## Phase 5: CC Permissions & Write-Gating

### Goal

Lock down Claude Code's ability to write to external services while preserving full autonomy inside the container. After this phase, Claude can do anything locally but cannot push code, create PRs, or mutate remote state without explicit approval.

### Approach Options (decide at implementation time)

**Option A: `--dangerously-skip-permissions` + hooks**
- Claude runs with no permission prompts at all
- A `PreToolUse` hook script inspects every Bash command and blocks write operations
- Simpler: no allowlist maintenance
- Risk: if a hook fails to catch something, there is no fallback

**Option B: Very permissive settings (no `--dangerously-skip-permissions`)**
- Broad `allow` list covering all read operations, local commands, web fetches, etc.
- Specific `deny` or `ask` rules for write operations (git push, gh api POST, etc.)
- Claude still prompts for truly unknown commands
- More conservative: unknown commands default to asking

Either option uses the same write-gating logic. The question is whether unknown/uncategorised commands should silently succeed (Option A) or prompt (Option B).

### What to Build

**Write-gating hook** (`claude/hooks/gate-writes.sh`):
- Receives tool call JSON on stdin
- For Bash commands, inspects the command string
- Blocks (exit 2 or deny response): `git push`, `git push *`, `gh pr create`, `gh issue create`, `gh api` with `-X POST|PUT|DELETE|PATCH` or `--method POST|PUT|DELETE|PATCH`, `curl -X POST` to external URLs, any publish/deploy commands
- Allows everything else
- Returns a clear reason when blocking ("Write operation blocked: git push requires confirmation")

**Update Claude settings.json** with hook configuration and either a permissive allowlist (Option B) or minimal config (Option A).

**Update `denv claude`** to pass `--dangerously-skip-permissions` if Option A is chosen.

### How to Verify

1. Start Claude in the container
2. Ask Claude to read a GitHub repo (`gh api` GET) — should work without prompts
3. Ask Claude to create a PR (`gh pr create`) — should be blocked with clear message
4. Ask Claude to push code (`git push`) — should be blocked
5. Ask Claude to install a package (`bun install express`) — should work
6. Ask Claude to fetch a web page (`curl`, `WebFetch`) — should work
7. Ask Claude to run arbitrary local commands — should work
8. Test edge cases: `gh api -X POST`, `curl --request POST`, piped commands

---

## Phase 6: Refinement & Testing

### Goal

Test with real projects of various types, fix issues, tune the setup based on actual usage.

### Activities

- Test with a Node/TypeScript web project (verify port forwarding, dev server, Playwright)
- Test with a Python project (verify uv, venvs, package installation)
- Test with a Rust project (verify cargo, compilation, toolchain management)
- Test kick-off-and-walk-away workflow (Claude researches something autonomously)
- Test multiple simultaneous containers (resource usage, port conflicts)
- Tune dotfiles based on actual shell usage inside containers
- Tune Claude CLAUDE.md based on how Claude actually behaves in the environment
- Tune write-gating rules based on false positives/negatives
- Document any gotchas or workarounds
- Set up the image-sharing workaround (pngpaste + keyboard shortcut) if desired
- Consider whether `denv` needs any additional commands based on real usage patterns
