# denv

Isolated Docker containers for running Claude Code. Your project files are bind-mounted from the Mac so you edit them locally as normal (Cursor, Finder, terminal). The container is Claude's workspace — pre-configured with all the runtimes and tools it needs to work autonomously.

The core problem: giving Claude Code broad permissions on a bare Mac risks accidental damage to your host filesystem and potential data exfiltration. The solution: run Claude Code inside a container where it can do anything it wants, while gating operations that write to external services.

Requires [OrbStack](https://orbstack.dev/) (or Docker Desktop) on macOS.

## Quick start

```sh
# Clone and put denv on your PATH
git clone <repo-url> ~/dev/denv
ln -s ~/dev/denv/denv ~/.local/bin/denv

# Create a container for an existing project
denv create ~/dev/my-project

# Shell in
denv my-project

# Or start Claude directly
denv claude my-project
```

## Commands

| Command | Description |
|---|---|
| `denv create <path>` | Create a container for the project at `<path>`. Builds the image if needed, then runs GitHub auth. |
| `denv shell <project>` | Open a zsh shell in the container (starts it if stopped). |
| `denv <project>` | Shortcut for `denv shell <project>`. |
| `denv claude <project> [args]` | Run `claude` inside the container, passing any extra args. |
| `denv start <project>` | Start a stopped container. |
| `denv stop <project>` | Stop a running container. |
| `denv rm <project>` | Remove a container (project files on Mac are untouched). |
| `denv rebuild [project]` | Rebuild the base image. If a project is specified, recreate that container from the new image. |
| `denv ls` | List all denv containers with status and project path. |
| `denv scaffold <name> [path]` | Create a new project at `<path>/<name>` (default `~/dev/<name>`) with template files, `git init`, and a container. |
| `denv update-plugins <project>` | Copy the latest plugin install script into the container and run it. |

## How it works

```
Mac (host)
├── ~/dev/my-project/          ← you edit files here
│
└── Docker container (denv-my-project)
    ├── /workspace/            ← bind mount of ~/dev/my-project (same files)
    └── /home/dev/             ← baked into image (runtimes, config, dotfiles)
```

All containers share a single base image (`denv-base`). The image is built from the `Dockerfile` in this repo.

- **Bind mount**: project directory from Mac to `/workspace` in the container
- **No home volume**: `/home/dev` is baked into the image with standard paths for all runtimes. This means `denv rebuild` resets auth and shell history, but tool installation paths just work.
- **Networking**: OrbStack gives each container a `denv-<project>.orb.local` domain — access dev servers at e.g. `denv-my-project.orb.local:3000` with no port mapping needed.

### What's in the image

**Runtimes**: Node.js (fnm), Bun, Python (uv), Rust (rustup), Go

**CLI tools**: `gh`, `rg` (ripgrep), `fd`, `bat`, `tree`, `jq`, `yq`, `ncdu`, `sqlite3`, `miller`, `vips`, Claude Code

**Browser automation**: Playwright with Chromium, rodney

**Python tools**: showboat, chartroom (via `uv tool install`)

**Claude Code config**: global instructions, settings, MCP servers (Context7), plugin install script

### Persistence

| Scenario | Project files | Home dir (auth, tools, history) |
|---|---|---|
| `denv stop` / `denv start` | Safe (on Mac) | Preserved |
| `denv rebuild` | Safe (on Mac) | Reset to new image |
| `denv rm` | Safe (on Mac) | Gone |

## First-time setup after `denv create`

`denv create` handles GitHub auth automatically. Claude auth and plugins require a manual step:

```sh
denv my-project
claude            # then use /login to authenticate
/opt/denv/install-claude-plugins.sh
```

After `denv rebuild`, re-run the auth steps above.
