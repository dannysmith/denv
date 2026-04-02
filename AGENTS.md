# AI Agent Instructions

This is the `denv` project — a CLI tool and Docker image for creating isolated development containers where Claude Code (or other AI agents) can run with near-full autonomy on macOS.

## What this project is

The `denv` CLI manages Docker containers (via OrbStack) where AI coding agents work on projects. Project files are bind-mounted from the Mac, so the user edits locally while the agent operates inside the container. The container is pre-configured with runtimes (Node, Python, Rust, Go), CLI tools, Claude Code config, and a write-gating hook that requires user confirmation before pushing code or mutating GitHub state.

## Repo structure

```
denv                       ← the CLI script (bash), runs on the Mac
Dockerfile                 ← builds the denv-base image (Ubuntu 24.04)
claude/
  CLAUDE.md                ← global Claude Code instructions baked into the image
  settings.json            ← Claude Code settings (permissions, hooks, plugins)
  .claude.json             ← MCP server config (Context7)
  hooks/
    gate-writes.sh         ← PreToolUse hook that gates external write operations
dotfiles/
  zshrc                    ← container shell config (prompt, PATH, aliases)
  gitconfig                ← container git config (gh credential helper, aliases)
  gitignore_global         ← container global gitignore
scripts/
  entrypoint.sh            ← container entrypoint
  install-claude-plugins.sh ← installs Claude Code plugins (skills, marketplaces)
scaffold/                  ← template files for `denv scaffold` command
PLAN.md                    ← project plan with architecture docs and phase history
```

## Key design decisions

- **No home volume.** `/home/dev` is baked into the image, not a persistent volume. This means `denv rebuild` resets auth and history, but all runtimes install to standard default paths (`~/.cargo`, `~/.local`, etc.) with no workarounds. This matters because agents frequently install tools at runtime.
- **Write-gating via hooks, not hard blocking.** The `gate-writes.sh` hook uses `permissionDecision: "ask"` (not `"deny"`), so the user can approve write operations case-by-case. The broad `Bash(*)` allow rule means everything local runs without prompts.
- **Docker labels for metadata.** Container labels (`denv.project`, `denv.path`, `denv.created`) store all state needed for `denv rebuild` to recreate a container with the correct bind mount. No external state files.
- **Single base image.** All containers share `denv-base`. Disk layers and page cache are shared across containers.
- **`.orb.local` DNS uses mDNS.** OrbStack resolves container domains via Bonjour, not `/etc/resolver`. If `.orb.local` stops resolving (common after sleep/wake or VPN reconnects), flush the cache: `sudo killall -HUP mDNSResponder && sudo dscacheutil -flushcache`

## Working on this project

- The `denv` script is plain bash. It runs on the Mac (not inside a container).
- The Dockerfile, dotfiles, Claude config, and hooks are all baked into the image at build time. Changes require `denv rebuild` to take effect in existing containers.
- `scaffold/` contains template files copied into new projects by `denv scaffold`. The `__PROJECT_NAME__` placeholder in `README.md` is replaced with the actual project name.
- `PLAN.md` contains the full architecture documentation and phase history. Refer to it for context on why things are the way they are.
