# Docker Sandboxes Research Findings

Research date: 2026-03-12

Sources: Docker official docs (docs.docker.com/ai/sandboxes/*), Docker blog post, docker/desktop-feedback GitHub issues.

---

## 1. What Are Docker Sandboxes?

Docker Sandboxes are **lightweight microVMs** designed to run AI coding agents (Claude Code, Codex, Copilot, Gemini, etc.) in isolated environments. Each sandbox is a dedicated virtual machine with:

- Its own kernel (separate from host)
- Its own Docker daemon (isolated from host Docker)
- Bidirectional file sync with a host workspace directory
- Outbound internet access through a host-side proxy
- A non-root `agent` user with sudo access

**Key distinction**: Sandboxes are microVMs, NOT containers. They do not appear in `docker ps`. Use `docker sandbox ls` instead.

### Requirements

- **Docker Desktop 4.58+** (required -- see OrbStack section below)
- **macOS** (production) or **Windows** (experimental)
- **Linux**: NOT supported for microVM-based sandboxes. Legacy container-based sandboxes only.

---

## 2. File Sync Mechanism

### How It Works

- **Bidirectional file copying** (NOT volume mounting). Files are copied between host and VM.
- Workspace syncs to the **same absolute path** inside the sandbox (e.g., `~/dev/my-project` on host appears at `~/dev/my-project` in the sandbox).
- Edit a file on the host, the agent sees it. The agent modifies a file, you see the change on the host.

### Multiple Workspaces

You can mount multiple workspaces, including read-only ones:
```bash
docker sandbox run claude ~/my-project ~/docs:ro
```

### What Is NOT Documented

The docs provide **no information** about:
- **Sync latency** (how fast changes propagate)
- **Handling of large directories** (node_modules, .git, vendor)
- **Exclude/ignore patterns** (no `.sandboxignore` or similar mechanism exists)
- **Performance characteristics** of the sync

### Known File Sync Issues (from GitHub issues)

**CRITICAL: Git index corruption** (issue #62):
- The bidirectional file sync has been reported to **corrupt the `.git/index` file**, causing `git status` to segfault on the host.
- Root cause: likely race conditions or partial writes during sync of binary files.
- Workaround: `rm .git/index && git reset`
- Users also report **random file corruption/truncation** during large file operations inside the sandbox.
- One user reported files "working normally and getting truncated just a second later."

**No ignore/exclude support** (issue #163):
- There is currently **no way to exclude files from sync** (no `.sandboxignore`).
- This is an open feature request.
- Workaround: structure your project so sensitive dirs like `.git` are in a parent directory, and only mount the subdirectory containing source code.

**Implications for the use case**: The file sync corruption issue with `.git` is a serious concern. Since the sync has no exclude mechanism, ALL files in the workspace are synced bidirectionally, including `.git/`, `node_modules/`, etc. This could cause:
1. Performance issues with large directories
2. Corruption of binary files (like git index)
3. Unnecessary syncing of thousands of files in `node_modules`

---

## 3. Running Things Directly in the MicroVM

### Architecture: Container Inside a MicroVM

The docs are somewhat contradictory on this, but the clearest statement is from the getting started guide: **"Docker started the Claude Code agent as a container inside the sandbox VM."**

The architecture is:
```
Host macOS
  └── MicroVM (via virtualization.framework)
       ├── Private Docker daemon
       └── Agent container (Claude Code runs here)
            └── Workspace files synced here
```

When you `docker sandbox exec -it <name> bash`, you get a shell **inside the agent container** (which is inside the microVM). The exec command uses container-style flags (`--user`, `--workdir`, `--env`, `-it`, etc.).

### What You Can Do Inside

Despite running in a container-within-a-VM, you have significant capabilities:
- **sudo access**: The `agent` user has sudo privileges
- **Install system packages**: `apt-get install` works
- **Install language packages**: npm, pip, cargo, etc.
- **Run services**: dev servers, databases, etc.
- **Run Docker commands**: build images, run containers (using the private Docker daemon inside the VM)
- **The agent effectively has root-level control** within its sandbox

### Base Environment (Ubuntu 25.10)

Pre-installed tools in the default `claude-code` template:
- Docker CLI (with Buildx and Compose)
- Git, GitHub CLI (`gh`)
- Node.js
- Go
- Python 3
- uv (Python package manager)
- make, jq, ripgrep
- Package managers: apt, pip, npm

### Shell Agent

The `shell` agent type provides a "minimal environment for manual setup" -- essentially a sandbox without an AI agent, giving you a bare interactive shell. This could be useful for manual dev work or custom setups.

```bash
docker sandbox run shell ~/my-project
```

---

## 4. Persistence

### What Persists Across Stop/Start

When you `docker sandbox stop` and later `docker sandbox run` again:
- **All installed packages** (apt, npm, pip, etc.)
- **Docker images/containers** created inside the sandbox
- **Agent state** (credentials, configuration, command history)
- **Workspace file changes** (synced back to host)
- **Any files outside the workspace** (e.g., `/tmp`, `/home/agent/`)

Sandboxes persist **until explicitly removed**.

### What Is Lost on Removal

`docker sandbox rm <name>` **deletes the entire VM and all its contents**. Everything is gone:
- All installed packages
- All Docker images built inside
- All files not in the synced workspace
- Agent configuration and auth state

### Full Reset

`docker sandbox reset` deletes **all sandboxes** plus:
- All VM state directories (`~/.docker/sandboxes/vm/`)
- Image cache (`~/.docker/sandboxes/image-cache/`)
- All internal registries

---

## 5. Resource Usage

### RAM: 4GB Hard Cap (MAJOR LIMITATION)

**Each sandbox gets approximately 4GB of RAM** with no way to configure this.

- This is **hardcoded** and does NOT respect Docker Desktop's global memory settings.
- There is **no `--mem` or `--cpu` flag** (requested in issue #92).
- No swap is configured, and you **cannot enable swap from inside the sandbox** (swapon is blocked by seccomp, CAP_SYS_ADMIN is not available, /sys is read-only).
- Under heavy workloads (Java/Node builds, large compilations), the **OOM killer terminates the sandbox** (exit code 137).
- Users report this is a **blocking issue** for many real-world workloads. One user noted even "casual conversations" can crash the sandbox.
- Issue #121 has significant community concern and upvotes.

### CPU

No specific documentation on CPU allocation. The sandbox likely shares host CPUs but this is not configurable.

### Disk

- Each sandbox maintains separate storage for VM disk, Docker images, and container layers.
- **Multiple sandboxes do NOT share images or layers** -- each has its own isolated storage.
- Disk grows based on package installations and image builds.
- No documented disk quotas.

### Implications for the Use Case

Running 5-10 project sandboxes simultaneously would mean:
- 5-10 separate microVMs, each with ~4GB RAM allocation
- 5-10 separate copies of all installed tools and packages
- Significant disk usage since images/layers are not shared
- The 4GB limit is a real problem for non-trivial build tasks

---

## 6. Networking

### Outbound Access

- Sandboxes have **outbound internet access** through the host's network connection.
- All traffic goes through an **HTTP/HTTPS filtering proxy** at `host.docker.internal:3128`.
- The proxy performs **SSL inspection (MITM)** and automatically injects credentials for supported providers (OpenAI, Anthropic, Google, GitHub) -- keeping API keys on the host, not in the sandbox.

### Network Policies

You can control network access with allow/deny lists:
```bash
# Block specific hosts
docker sandbox network proxy <name> --block-host example.com

# Block CIDR ranges
docker sandbox network proxy <name> --block-cidr 10.0.0.0/8

# Deny-by-default with allowlist
docker sandbox network proxy <name> --policy deny --allow-host api.anthropic.com

# Bypass MITM inspection for specific hosts
docker sandbox network proxy <name> --bypass-host trusted-service.com
```

### Port Forwarding: NOT SUPPORTED (MAJOR LIMITATION)

**There is NO port forwarding from host to sandbox.**

- Sandboxes cannot expose ports to the host.
- MicroVM IPs (192.168.65.x) are NOT routable from the Mac host.
- You cannot access dev servers (e.g., `localhost:3000`) running inside the sandbox from your Mac browser.
- `docker sandbox exec` with socat does not support bidirectional streaming.
- This is listed on Docker's roadmap as a planned feature.
- Issues #91 and #126 track this request.
- **Workaround**: One user created an SSH-over-TLS tunnel (github.com/DenysGonchar/ssh-over-tls).

### Sandbox Isolation

- Sandboxes **cannot communicate with each other** (each has its own private network namespace).
- Sandboxes **cannot access host's localhost services**.

### Docker-in-Docker Networking Issues

Building Docker images inside the sandbox is broken for network-dependent operations (issue #165):
- `docker build` RUN steps have **no outbound network** (only FROM/image pulls work).
- `apt-get update`, `npm install`, `pip install` etc. all fail during Docker builds inside the sandbox.
- The VM itself has network access; only the Docker-in-Docker build layer is broken.
- Workaround exists but requires manual proxy configuration and CA cert injection.

---

## 7. Templates

### Default Template

The default Claude Code template (`docker/sandbox-templates:claude-code`) includes Ubuntu 25.10 + the pre-installed tools listed above.

### Custom Templates via Dockerfile

```dockerfile
FROM docker/sandbox-templates:claude-code
USER root

RUN apt-get update && apt-get install -y \
    build-essential \
    zsh \
    ffmpeg \
    sqlite3 \
    tree \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install bun
RUN curl -fsSL https://bun.sh/install | bash

# Install additional Node packages
RUN npm install -g \
    playwright-cli

# Install Python tools
RUN pip3 install --no-cache-dir \
    defuddle

USER agent
```

Build and use:
```bash
docker build -t my-dev-template:v1 .
docker sandbox run -t my-dev-template:v1 claude ~/my-project
```

### Save Running Sandbox as Template

```bash
# Save to local Docker daemon
docker sandbox save my-sandbox my-template:v1

# Or export to tar
docker sandbox save -o template.tar my-sandbox my-template:v1
```

### Template Caching

- `--pull-template missing` (default): uses local if available, pulls otherwise
- `--pull-template always`: always pulls latest from registry
- `--pull-template never`: bypasses host cache, pulls from registry per startup
- Cache persists across sandbox creation/deletion
- `docker sandbox reset` clears cached images

### Known Template Issue

**Claude configuration files are wiped on sandbox start** (issue #167):
- If you COPY `CLAUDE.md`, `settings.json`, or `claude.json` into `/home/agent/.claude/` in your Dockerfile, they are **blown away when the container starts**.
- There is currently no way to pre-configure Claude Code via the template system.
- This is a significant limitation for baking in organizational standards, MCP servers, or custom Claude configuration.

---

## 8. OrbStack Compatibility

**Docker Sandboxes require Docker Desktop. They do NOT work with OrbStack.**

- The `docker sandbox` command is a **Docker Desktop CLI plugin** (installed at `~/.docker/cli-plugins/docker-sandbox`).
- The sandboxes use Docker Desktop's built-in `sandboxd` daemon process.
- The microVMs use macOS `virtualization.framework` which is managed by Docker Desktop.
- No alternative Docker runtimes are mentioned as compatible.
- No GitHub issues found requesting OrbStack support.

If you currently use OrbStack, you would need to switch to (or additionally install) Docker Desktop to use sandboxes.

---

## 9. Complete CLI Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `docker sandbox run AGENT [PATH] [-- AGENT_ARGS]` | Create (if needed) and run an agent in a sandbox |
| `docker sandbox create AGENT PATH` | Create a sandbox without starting the agent |
| `docker sandbox stop NAME [NAME...]` | Stop sandbox(es) without removing them |
| `docker sandbox rm NAME [NAME...]` | Remove sandbox(es) and delete all VM contents |
| `docker sandbox ls [--json] [-q]` | List all sandboxes |
| `docker sandbox exec [-it] NAME COMMAND` | Execute a command inside a sandbox |
| `docker sandbox inspect NAME` | Show detailed sandbox info (JSON) |
| `docker sandbox save NAME TAG [-o FILE]` | Save sandbox as template image |
| `docker sandbox reset [-f]` | Delete ALL sandboxes and clean up all state |
| `docker sandbox network log` | Show network activity logs |
| `docker sandbox network proxy NAME [OPTIONS]` | Configure network access policies |
| `docker sandbox version` | Show sandbox plugin version |

### Key Flags for `docker sandbox run`

| Flag | Description |
|------|-------------|
| `--name NAME` | Custom sandbox name (default: `<agent>-<workdir>`) |
| `-t, --template IMAGE` | Custom template image |
| `--pull-template POLICY` | Image pull policy: `always`, `missing`, `never` |

### Key Flags for `docker sandbox exec`

| Flag | Description |
|------|-------------|
| `-i, --interactive` | Keep STDIN open |
| `-t, --tty` | Allocate pseudo-TTY |
| `-d, --detach` | Run in background |
| `-e, --env KEY=VAL` | Set environment variable |
| `--env-file FILE` | Read env vars from file |
| `-u, --user USER` | Run as specified user |
| `-w, --workdir DIR` | Set working directory |
| `--privileged` | Give extended privileges |

### Network Proxy Flags

| Flag | Description |
|------|-------------|
| `--policy allow/deny` | Default network policy |
| `--block-host DOMAIN` | Block specific domain |
| `--block-cidr CIDR` | Block IP range |
| `--allow-host DOMAIN` | Allow specific domain |
| `--allow-cidr CIDR` | Allow IP range |
| `--bypass-host DOMAIN` | Skip MITM proxy for domain |
| `--bypass-cidr CIDR` | Skip MITM proxy for IP range |

---

## 10. Limitations & Gotchas Summary

### Blocking / Critical Issues

1. **4GB RAM hard cap** -- cannot be configured, no swap, OOM kills under heavy workloads
2. **No port forwarding** -- cannot access dev servers from host browser (on roadmap)
3. **File sync corrupts git index** -- bidirectional sync of `.git/` binary files causes corruption
4. **No file sync ignore/exclude** -- all workspace files are synced, including `node_modules/`, `.git/`, etc.
5. **Claude config files wiped on start** -- cannot pre-configure CLAUDE.md or settings.json via templates
6. **Docker Desktop required** -- no OrbStack or alternative runtime support

### Significant Limitations

7. **No Linux support** for microVM-based sandboxes (on roadmap)
8. **Docker-in-Docker builds broken** -- RUN steps have no network, only image pulls work
9. **Environment variables not passed to microVM** -- daemon process doesn't inherit shell env; must be in shell profile AND Docker Desktop must be restarted
10. **Sandboxes cannot access host localhost services** -- no access to local databases, APIs, etc.
11. **No inter-sandbox communication**
12. **No shared images/layers between sandboxes** -- each sandbox has its own isolated Docker daemon and storage
13. **Host directory structure leaked** -- absolute paths are preserved, exposing your host directory names (issue #158)
14. **All agents marked "experimental"** -- breaking changes may occur between Docker Desktop versions

### Operational Considerations

15. **First run is slow** -- must download template image and initialize microVM
16. **`docker sandbox rm` is destructive** -- deletes all installed packages, Docker images, agent state
17. **Re-authentication required after removal** -- must re-run `gh login`, `claude login`, etc.
18. **No `--dangerously-skip-permissions` toggle** -- it's always on, cannot be disabled (issue #178)

---

## 11. Assessment: Suitability for Ring-Fenced Dev Environment

### What Works Well

- **Isolation model** is excellent -- hypervisor-level separation, private Docker daemon
- **Custom templates** allow pre-installing all your tooling
- **Persistence across stop/start** means you keep your environment between sessions
- **Claude Code runs with full permissions by default** (`--dangerously-skip-permissions`)
- **sudo access** inside the sandbox means full control of the environment
- **Multiple workspace mounts** with read-only option
- **Network policy controls** for security
- **`docker sandbox save`** lets you snapshot and reuse configured environments

### What Doesn't Work (for the specific use case)

1. **Cannot preview web apps** -- no port forwarding means you can't open `localhost:3000` from your Mac browser to see what Claude Code built. This is a dealbreaker for frontend/fullstack development.

2. **File sync is unreliable with git** -- the `.git/` corruption issue means you likely need `.git` outside the synced workspace, which complicates the workflow significantly.

3. **4GB RAM is insufficient** -- for projects involving builds (webpack, Rust compilation, Java, etc.), you will regularly hit OOM. This makes it unsuitable as a general-purpose dev environment for non-trivial projects.

4. **No file sync excludes** -- syncing `node_modules/` bidirectionally for every file change is wasteful and potentially problematic. You want `node_modules` to exist independently inside the sandbox.

5. **Cannot pre-configure Claude** -- your CLAUDE.md, settings.json, MCP configs get wiped. You'd need to set these up manually each time you create a sandbox, or find a workaround.

6. **Requires Docker Desktop** -- if you're an OrbStack user, this is a nonstarter without switching.

### Bottom Line

Docker Sandboxes are well-designed for the specific use case of **running an AI agent on a single task and reviewing the output**. They are **not yet mature enough** to serve as a general-purpose ring-fenced development environment because of the port forwarding gap, RAM limitations, and file sync issues. The product is still experimental and several of these limitations are on Docker's roadmap.

If the use case were purely "let Claude Code work on code autonomously and I'll review the file changes" -- with no need to run dev servers, no heavy builds, and willingness to keep `.git` out of the sync path -- it could work today. But as a full replacement for a local dev environment with the ringfencing benefits, it's not there yet.
