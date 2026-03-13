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

Each container has exactly **one mount**:

1. **Bind mount**: project directory from Mac → `/workspace` in container

There is no home directory volume. `/home/dev` lives in the container's writable layer and is baked into the image with all tools, dotfiles, and config. This means all runtimes (Rust, Python, Go, etc.) install to their standard default locations (`~/.cargo`, `~/.local`, `~/go`, etc.) with no workarounds needed.

**Trade-off**: `denv rebuild` (destroying and recreating a container from a new image) will lose auth state (Claude, gh), shell history, and any tools Claude installed during sessions. Re-auth takes ~30 seconds and is infrequent. This is a worthwhile trade for completely standard tool installation paths, which matters because Claude will frequently install tools at runtime.

**Persistence by scenario**:

| Scenario | Project files | Home dir (auth, tools, history) | System (apt packages, global bins) |
|---|---|---|---|
| `denv stop` / `denv start` | Safe (on Mac) | Preserved (container layer) | Preserved |
| `denv rebuild` (new base image) | Safe (on Mac) | Reset to new image | Reset to new image |
| `denv rm` | Safe (on Mac) | Gone | Gone |

### Filesystem Layout (inside container)

```
/workspace/                     ← bind-mounted project directory
/home/dev/                      ← container layer (from image, standard paths)
  ├── .claude/                  ← Claude Code config + auth
  ├── .config/gh/               ← GitHub CLI auth
  ├── .cargo/                   ← Rust toolchain
  ├── .local/                   ← uv-managed Python, user binaries
  ├── go/                       ← GOPATH (go install targets)
  ├── .zshrc, .gitconfig, etc.  ← shell config
/opt/denv/                      ← entrypoint, hooks
```

### Networking

OrbStack gives each container a `<container-name>.orb.local` domain where all ports are accessible without any `-p` flags (e.g., `denv-my-project.orb.local:3000`). For `localhost` access, explicit `-p` mapping may still be needed — verify in Phase 1. The `.orb.local` approach is preferable anyway since it avoids port conflicts when multiple containers run dev servers on the same port number.

### Container Naming

- Container: `denv-<project-name>` (where project-name is the directory name from the path given to `denv create`)
- Docker labels on the container store metadata (original project path, creation date) so `denv rebuild` can recreate with the correct bind mount without external state files

### Dependency Directories (node_modules, etc.)

Project-level dependency directories (`node_modules`, `venv`, `target`, etc.) live inside the bind-mounted project directory. Both the container and the Mac see them. No special volume treatment. OrbStack's VirtioFS bind mount performance is ~80-95% of native, which is acceptable. This keeps things simple and means you can run/build both inside the container and locally on the Mac.

### Image Sharing with Claude Code

Clipboard image paste does not work in container terminals. The practical workaround is a keyboard shortcut on the Mac that saves the clipboard to a known path accessible from the container (via the bind mount or a shared location). Implementation details deferred — not a critical-path feature.

---

## Phase 1: Base Repo & Dockerfile [✅ DONE]

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
- Install Claude Code (`WORKDIR /tmp` first, then `curl -fsSL https://claude.ai/install.sh | bash` — installing from `/` hangs because the installer scans the filesystem)
- Install GitHub CLI (`gh`)
- Create non-root user `dev` with sudo access and zsh as default shell. Match UID to macOS default (501) to avoid bind mount permission issues — verify in testing.
- Set `WORKDIR /workspace`

**entrypoint.sh** — minimal:
- Ensure correct ownership of `/home/dev` volume
- Exec into zsh (or whatever command was passed)

**Volume setup**: bind mount for project dir, named volume for home.

### How to Verify

1. Build the image: `docker build -t denv-base .`
2. Create a test project: `mkdir ~/dev/test-project && cd ~/dev/test-project && git init && echo "# Test" > README.md`
3. Run container manually: `docker run -it --name denv-test-project -v ~/dev/test-project:/workspace denv-base`
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

### Phase 2a: Node + Bun (verify existing setup) [✅ DONE]

Node.js and Bun are already installed from Phase 1. Verify they work correctly for global tool installation (needed by later steps). Confirm `npx`/`bunx` work.

### Phase 2b: Python + uv [✅ DONE]

- Install uv via COPY from official distroless image: `COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/`
- Install Python via uv: `uv python install` (no apt python3 needed — uv manages Python entirely)
- This replaces python3, pip, venv, pyenv, pipx, poetry — uv handles all of it
- `uvx` runs Python CLI tools on-demand without global installs; `uv tool install` for persistent global installs
- Verify: `uv --version`, `python3 --version` (via uv-managed Python), `uvx --version`

### Phase 2c: Rust [✅ DONE]

- Install Rust via rustup as the `dev` user: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`
- This gives us `rustc`, `cargo`, and the ability to `cargo install` tools
- Verify: `rustc --version`, `cargo --version`

### Phase 2c2: Go [✅ DONE]

- Install Go via official tarball from go.dev (the recommended method)
- Useful beyond Go projects: many developer tools are written in Go (yq, rodney, lazygit, glow, etc.) and Claude can `go install` them on the fly
- Verify: `go version`

### Phase 2d: CLI tools [✅ DONE]

Install via apt (all available in Ubuntu 24.04 repos):
- `ripgrep` (binary: `rg`) — fast recursive grep
- `fd-find` (binary: `fdfind`, needs symlink to `fd`) — fast file finder
- `bat` (binary: `batcat`, needs symlink to `bat`) — cat with syntax highlighting
- `tree` — directory tree viewer
- `ncdu` — ncurses disk usage analyzer (v1.x from apt; v2.x would need manual install)
- `sqlite3` — SQLite CLI (~570 KB, minimal)
- `libvips-tools` — image processing CLI (~50 MB with deps)
- `miller` — CSV/JSON/tabular data processor (~33 MB)

Install via `go install`:
- `yq` — YAML/JSON/XML processor. **Do NOT use apt** — the `yq` in apt is a different, unrelated Python tool. Install via `go install github.com/mikefarah/yq/v4@latest`
- `rodney` — headless Chrome automation CLI (Simon Willison). Install via `go install github.com/simonw/rodney@latest`. Needs Chrome/Chromium (provided by Playwright step)

Install via `uv tool install` (persistent global Python CLI tools):
- `showboat` — executable markdown demo builder (Simon Willison)
- `chartroom` — data-to-chart CLI using matplotlib (Simon Willison)

Not including:
- `ffmpeg` — ~100+ MB of codec deps; can be apt-installed on demand in containers that need it
- `xsv` — archived/unmaintained; miller + sqlite-utils covers CSV work
- `dust` — ncdu covers disk usage analysis

### Phase 2e: Playwright + Chromium [✅ DONE]

- Installed `@playwright/cli` globally via bun (`bun install -g @playwright/cli`)
- Browsers installed using the exact playwright version bundled with @playwright/cli to avoid revision mismatch
- Browsers stored in `/opt/playwright-browsers` (accessible to dev user)
- `PLAYWRIGHT_MCP_BROWSER=chromium` env var configured — full Chrome is x86-only on Linux, bundled Chromium works on ARM64
- `rodney` (Simon Willison's headless Chrome CLI) installed via `go install`
- Docker runtime considerations: containers need `--init` and `--ipc=host` flags for Chromium stability
- Headless mode only (headed mode can be done locally on the Mac instead)

### Phase 2f: Dotfiles

Create `dotfiles/` directory in repo with baseline config files. User will manually review and add personal aliases/preferences.

- `zshrc` — PATH setup for all runtimes (fnm, cargo, bun, uv, ~/.local/bin), fnm init, basic aliases (`ls` with `--color=auto`, `g`=git, etc.), compinit for tab completion
- `gitconfig` — pull rebase, verbose commits, `gh auth git-credential` for HTTPS auth, colors enabled
- `gitignore_global` — OS files, editor files, env files, *.local and *.local.*

### Phase 2g: Prompt, terminal colors & TUI support

**Terminal/color setup**:
- Install the `xterm-ghostty` terminfo entry in the image so `TERM=xterm-ghostty` works when connecting from Ghostty
- Set `COLORTERM=truecolor` in the environment
- Entrypoint or zshrc falls back gracefully to `xterm-256color` if the terminfo for the connecting terminal isn't present

**Prompt** (replicating the user's local Oh My Zsh theme without OMZ):
- Pure zsh prompt using `vcs_info` for git status (branch name, dirty indicator)
- Style: newline, blue cwd, git info (red branch, dirty marker), newline, green/red arrow
- Add a container indicator showing the denv project name (e.g. derived from container hostname or an env var)
- No Oh My Zsh dependency — just zsh builtins and `vcs_info`

current macos zsh prompt (loaded via oh-my-zsh custom theme)

```sh
NEWLINE=$'\n'

PROMPT="${NEWLINE}%{$fg[blue]%}%~%{$reset_color%}"
PROMPT+=' $(git_prompt_info)'
PROMPT+="${NEWLINE}"
PROMPT+='%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} ) '

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}%1{✗%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
```

### Phase 2h: Entrypoint & dotfiles in image

Since there is no home volume, dotfiles are simply baked into the image via the Dockerfile (`COPY dotfiles/ ...`). No version-stamp sync logic needed.

- Copy dotfiles into `/home/dev/` during image build
- Entrypoint remains minimal: just exec the provided command
- User manually reviews dotfile templates before finalizing

### Phase 2i: Minimal `denv` script (for testing)

- `denv create <path>` — runs `docker run` with correct mounts, naming, `--init`, and `--ipc=host` flags
- `denv shell <project>` — runs `docker exec -it` into existing container (starts it first if stopped)
- Add to PATH or symlink for convenience

### Phase 2j: Manual testing

1. Rebuild image, create test container via `denv create`
2. Verify all runtimes: `node`, `bun`, `python3`, `rustc`, `uv`, `cargo`
3. Verify all CLI tools: `rg`, `fd`, `bat`, `tree`, `ncdu`, `sqlite3`, `yq`, etc.
4. Verify Playwright: Claude session inside container uses Playwright to visit a website
5. Verify OrbStack networking: run `python3 -m http.server 8000`, access from Mac via `<container>.orb.local:8000`
6. Verify shell: prompt looks right, git info works, colors work, tab completion works
7. Verify stop/start persistence of auth, history, installed tools

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
- Copy Claude config into `/home/dev/.claude/` during image build
- Config is baked into the image (no volume sync needed)

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
| `denv rm <project>` | Remove container. |
| `denv rebuild [project]` | Rebuild base image. If project specified, recreate that container. |
| `denv ls` | List all denv containers with status (running/stopped) |
| `denv scaffold <name> [path]` | Create a new project directory at `<path>/<name>` (default `~/dev/<name>`), populate with template files, `git init`, then `denv create`. |

**Scaffold templates** (`scaffold/` in repo):
- `README.md` — minimal project readme
- `AGENTS.md` — Basic project instructions
- `CLAUDE.md` - Just "@AGENTS.md"
- `.gitignore` — sensible defaults
- `docs/tasks-todo/.gitkeep`
- `docs/tasks-done/.gitkeep`

**Installation**: the script lives in the repo. User symlinks it to somewhere on PATH (e.g., `ln -s ~/dev/denv/denv ~/.local/bin/denv`).

### Design Notes

- `denv create` should check if a container already exists and warn/skip
- `denv shell` and `denv claude` should auto-start a stopped container before exec-ing
- `denv rebuild` should: rebuild the image, stop the container, remove it, create a new container from the new image with the same mounts (note: auth state will need to be re-done)
- `denv ls` should show: project name, container status, project path
- Error messages should be clear and suggest the right command

### How to Verify

1. `denv create ~/dev/test-project` — creates container
2. `denv ls` — shows the container
3. `denv test-project` — opens shell
4. `denv claude test-project` — starts Claude session
5. `denv stop test-project` / `denv start test-project` — lifecycle works
6. `denv rebuild test-project` — new image, container recreated
7. `denv scaffold new-idea` — creates `~/dev/new-idea/` with template files and a container
8. `denv rm test-project` — cleans up

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
