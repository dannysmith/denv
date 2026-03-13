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
    ├── /home/dev/             ← baked into image (reset on rebuild)
    │   ├── .claude/           ← Claude auth + runtime state
    │   ├── .config/gh/        ← GitHub CLI auth
    │   ├── .zshrc             ← shell config
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

OrbStack gives each container a `<container-name>.orb.local` domain where all ports are accessible without any `-p` flags (e.g., `denv-my-project.orb.local:3000`). No `-p` port mapping is used. The `.orb.local` approach avoids port conflicts when multiple containers run dev servers on the same port number.

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
- Exec into zsh (or whatever command was passed)

**Volume setup**: bind mount for project dir. No home volume — `/home/dev` is baked into the image.

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

## Phase 2: Dotfiles & Dev Tools  [✅ DONE]

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

### Phase 2f: Dotfiles [✅ DONE]

Create `dotfiles/` directory in repo with baseline config files. User will manually review and add personal aliases/preferences.

- `zshrc` — PATH setup for all runtimes (fnm, cargo, bun, uv, ~/.local/bin), fnm init, basic aliases (`ls` with `--color=auto`, `g`=git, etc.), compinit for tab completion
- `gitconfig` — pull rebase, verbose commits, `gh auth git-credential` for HTTPS auth, colors enabled
- `gitignore_global` — OS files, editor files, env files, *.local and *.local.*

### Phase 2g: Prompt, terminal colors & TUI support [✅ DONE]

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

### Phase 2h: Entrypoint & dotfiles in image [✅ DONE]

Since there is no home volume, dotfiles are simply baked into the image via the Dockerfile (`COPY dotfiles/ ...`). No version-stamp sync logic needed.

- Copy dotfiles into `/home/dev/` during image build
- Entrypoint remains minimal: just exec the provided command
- User manually reviews dotfile templates before finalizing

### Phase 2i: Minimal `denv` script (for testing) [✅ DONE]

- `denv create <path>` — runs `docker run` with correct mounts, naming, `--init`, and `--ipc=host` flags
- `denv shell <project>` — runs `docker exec -it` into existing container (starts it first if stopped)
- Add to PATH or symlink for convenience

### Phase 2j: Manual testing  [✅ DONE]

1. Rebuild image, create test container via `denv create`
2. Verify all runtimes: `node`, `bun`, `python3`, `rustc`, `uv`, `cargo`
3. Verify all CLI tools: `rg`, `fd`, `bat`, `tree`, `ncdu`, `sqlite3`, `yq`, etc.
4. Verify Playwright: Claude session inside container uses Playwright to visit a website
5. Verify OrbStack networking: run `python3 -m http.server 8000`, access from Mac via `<container>.orb.local:8000`
6. Verify shell: prompt looks right, git info works, colors work, tab completion works
7. Verify stop/start persistence of auth, history, installed tools

---

## Phase 3: Claude Code Customisation [✅ DONE]

See [docs/archive/CLAUDE_SETUP_PLAN.md](docs/archive/CLAUDE_SETUP_PLAN.md) for the full plan.

Configured Claude Code inside the container with global instructions (`claude/CLAUDE.md`), settings (`claude/settings.json`), MCP config (Context7), and a reusable plugin installation script (`scripts/install-claude-plugins.sh`). `denv create` now handles GitHub auth automatically; Claude auth and plugin install are manual steps after first shell-in.

**Deviation from plan:** `claude auth login` doesn't work via `docker exec` (no paste prompt for OAuth code). Users must run `claude` interactively and use `/login` instead.

---

## Phase 4: Complete the `denv` CLI [✅ DONE]

Added all remaining lifecycle commands (`start`, `stop`, `rm`, `rebuild`, `ls`, `scaffold`) to the `denv` CLI. Extracted `create_container()` and `ensure_exists()` helpers to share logic between `create` and `rebuild`. Created `scaffold/` directory with template files for new project bootstrapping.

---

## Phase 5: CC Permissions & Write-Gating [✅ DONE]

Went with Option B (permissive allow list + hook). Added a `PreToolUse` hook (`claude/hooks/gate-writes.sh`) that intercepts Bash commands and returns `permissionDecision: "ask"` for write operations to external services (git push, gh pr/issue/release mutations, gh api with mutating methods, npm/cargo publish). All local operations remain auto-approved via the `Bash(*)` allow rule. The hook is baked into the image at `/opt/denv/hooks/gate-writes.sh`.

**Deviation from plan:** Used `permissionDecision: "ask"` (user confirmation prompt) instead of `"deny"` (hard block). This lets the user approve write operations case-by-case when they want Claude to push or create PRs. Also skipped gating `curl -X POST` — too many legitimate local uses and fragile to pattern-match.

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
