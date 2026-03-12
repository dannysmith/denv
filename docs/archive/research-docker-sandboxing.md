# Docker-Based Sandboxing: Patterns, Performance & Persistence

> **Context**: Focused research on Docker-specific patterns for AI coding agent sandboxing. Covers shared base image approaches (Docker Sandboxes, Anthropic devcontainer, Trail of Bits devc, etc.), bind mount performance benchmarks on macOS, Docker-in-Docker options, container persistence strategies, and RAM/disk sharing characteristics across multiple containers.

## 1. Shared Base Image + Per-Project Container Patterns

### Pattern A: Docker Sandboxes (Official Docker Product, Jan 2026)

Docker's first-party solution uses **microVMs, not containers**. Each sandbox gets its own lightweight VM with its own Linux kernel and its own private Docker daemon. This is the strongest isolation available without full VMs.

**How it works internally:**
- The `sandboxd` daemon listens on `~/.docker/sandboxes/sandboxd.sock`
- API: `POST /vm` (create), `GET /vm` (list), `DELETE /vm/{name}` (destroy)
- Each VM gets its own Docker daemon socket at `~/.docker/sandboxes/vm/<name>/docker.sock`
- File sharing uses **bidirectional file synchronization, NOT bind mounts** -- files are copied between host and VM, preserving absolute paths
- Credentials are injected via an HTTPS filtering proxy at `host.docker.internal:3128` -- credentials never enter the VM
- Sandboxes persist until explicitly `docker sandbox rm`'d -- installed packages, Docker images, agent state all survive restarts

**Usage:**
```bash
docker sandbox create --template docker/sandbox-templates:claude-code myproject
docker sandbox run myproject -- claude --dangerously-skip-permissions
```

**Limitations:**
- macOS and Windows only (requires Docker Desktop 4.58+). No Linux support yet.
- Multiple sandboxes do NOT share Docker images or layers -- each VM has its own isolated storage, so disk consumption grows linearly per sandbox.
- Cannot reach host `localhost` services due to VM boundary.
- File sync (not bind mounts) means there is latency for large file trees.

### Pattern B: Anthropic's Official DevContainer

Anthropic publishes a reference `.devcontainer/` at `github.com/anthropics/claude-code/.devcontainer/`:

**Dockerfile** (key elements):
```dockerfile
FROM node:20
RUN apt-get install -y git gh iptables ipset iproute2 dnsutils jq vim fzf zsh ...
# Non-root user setup
USER node
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
# Firewall script for network isolation
COPY init-firewall.sh /usr/local/bin/
```

**devcontainer.json** (key elements):
```json
{
  "runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"],
  "mounts": [
    "source=claude-code-bashhistory-${devcontainerId},target=/commandhistory,type=volume",
    "source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume"
  ],
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096"
  },
  "postStartCommand": "sudo /usr/local/bin/init-firewall.sh"
}
```

**Network isolation** is done via iptables + ipset inside the container:
- Creates an `allowed-domains` ipset with GitHub IP ranges (fetched from `api.github.com/meta`), npm registry, Anthropic API, Sentry, VS Code Marketplace
- Default OUTPUT policy is DROP
- DNS and SSH are allowed
- localhost is allowed
- Everything else is REJECT'd
- Verified at startup by confirming `example.com` is unreachable but `api.github.com` works

### Pattern C: Trail of Bits claude-code-devcontainer

A community project with a CLI tool (`devc`) specifically designed for per-project Claude Code sandboxing:

**Key features:**
- Ubuntu 24.04 base with Node.js 22, Python 3.13, uv, ripgrep, fd, tmux, fzf, delta
- Persistent named volumes for `~/.claude`, `/commandhistory`, `~/.config/gh` -- survive container rebuilds
- Host `~/.gitconfig` mounted read-only
- `devc .` installs the template, `devc shell` opens a session, `devc rebuild` preserves volumes, `devc destroy` cleans up
- `devc sync` copies Claude session logs from containers back to host for `/insights`
- Two patterns: per-project isolation (one container per repo) or shared workspace (multiple repos in one container)

### Pattern D: textcortex/claude-code-sandbox (Archived)

A standalone CLI that copies (not mounts) the repo into the container for true isolation:
- Auto-discovers and forwards credentials (API keys, GitHub tokens, macOS Keychain)
- Creates timestamped git branches per session (`claude/<timestamp>`)
- Configuration via `claude-sandbox.config.json` for mounts, setup commands, environment vars
- Real-time commit monitoring with diff display
- Supports named container instances for concurrent sessions

### Pattern E: Anthropic's devcontainer-features

A Dev Container Feature for installing Claude Code into any devcontainer:
```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  }
}
```
Requires Node.js in the container. Can be combined with any base image.

---

## 2. Docker Bind Mounts from macOS: Performance in Practice

### Benchmark Data (MacOS M4 Pro, 48GB RAM, 2025)

| Runtime | Bind Mount (npm install) | vs Native |
|---------|------------------------|-----------|
| OrbStack | 4.22s | ~80% native |
| Docker Desktop (VirtioFS + file sync) | 3.88s | ~73% native |
| Docker Desktop (VirtioFS standard) | 9.53s | ~55% native |
| Lima | 8.99s | ~59% native |
| Docker Desktop (VMM hypervisor, beta) | 8.47s | ~62% native |
| Native macOS | 5.29s | 100% |

### OrbStack Specifics

OrbStack achieves **2-10x faster performance** than stock Docker Desktop for bind mounts, reaching **75-95% of native macOS speed** depending on the workload:

| Operation | OrbStack | Native macOS | % of Native |
|-----------|----------|-------------|-------------|
| pnpm install | 12.2s | 10.9s | 88% |
| yarn install | 9.8s | 7.9s | 77% |
| rm -rf node_modules | 4.0s | 3.6s | 87% |
| PostgreSQL pgbench | 8998 TPS | 11785 TPS | 76% |

**How OrbStack achieves this:** Rather than NFS or plain VirtioFS, OrbStack reduces per-syscall overhead by up to 10x with custom dynamic caching on top of VirtioFS. No file copying or synchronization delays. Files remain on the Mac filesystem with no duplication.

**Real-world reports:** Database-heavy tasks run 5x faster than Docker Desktop (36x improvement cited in some cases). Rails test suites 16% faster.

**OrbStack volume performance tip:** Named volumes store data on the Linux side directly and are significantly faster than bind mounts. Volume contents are accessible from macOS at `~/OrbStack/docker/volumes/` or via Finder's OrbStack tab. For paths that don't need host editing (node_modules, build caches), volumes are strongly preferred.

### Practical Implications for Your Use Case

Your pattern of mounting the project directory into the container while Claude works inside is the ideal bind mount scenario. The project directory is what you actively edit, and OrbStack handles this well. For heavy I/O directories like `node_modules` or `.git`, using named volumes (stored on the Linux side) will avoid the bind mount overhead entirely.

**The `consistency=delegated` flag** in bind mounts (used by Anthropic's devcontainer) tells Docker that the container's view of the filesystem can lag slightly behind the host -- this improves write performance when the container is doing most of the writing.

---

## 3. Docker-in-Docker: Limitations and Workarounds

### The Core Problem

Projects that themselves need Docker (running test databases, docker-compose stacks, building images) hit a wall in containers because the container doesn't have access to a Docker daemon.

### Approach 1: Mount Host Docker Socket (DANGEROUS)

```bash
docker run -v /var/run/docker.sock:/var/run/docker.sock myimage
```

**Never do this for AI agent sandboxing.** The agent gets full control of your host Docker daemon, can create privileged containers, and effectively has root on your host.

### Approach 2: Docker Sandboxes (Private Docker Daemon)

Docker Sandboxes solve this properly -- each microVM has its own Docker daemon. The agent can `docker build`, `docker compose up`, run test containers, etc. without accessing the host daemon. This is currently the only solution that provides Docker-in-Docker with hypervisor-level isolation.

**Limitation:** Images must be explicitly loaded into the sandbox via `docker save | docker load`. There's no shared image cache between sandboxes.

### Approach 3: Sysbox Runtime

Sysbox is an open-source replacement for `runc` that enables Docker-in-Docker without privileged mode:

```bash
docker run --runtime=sysbox-runc -it ubuntu:latest
# Inside this container, you can install and run Docker normally
```

**How it works:** Uses Linux user namespaces so root inside the container maps to an unprivileged user on the host. Partial procfs/sysfs virtualization and selective syscall trapping. The inner Docker daemon runs entirely in user space with no host kernel exposure.

**Performance:** Similar to regular `runc`. Nested containers have "excellent performance" with modest network I/O overhead from additional interfaces.

**Key advantage for your use case:** You can install Docker inside any Sysbox container without modifying the image, without privileged mode, without mounting the host socket. Run `apt-get install docker.io && dockerd &` inside the container and it just works.

**Limitations:**
- Linux only (no macOS/Windows)
- Requires installation on the Docker host (kernel module)
- Not compatible with Docker Desktop's Linux VM (would need to be installed inside the VM, which Docker Desktop doesn't expose)

### Approach 4: Podman (Rootless, Daemonless)

Podman can run inside containers without a daemon or root access:

```bash
# Inside a container with podman installed
podman run --rm alpine echo hello
```

Rootless by default, no daemon process, Docker-compatible CLI. However, running Podman inside a container still requires user namespace support.

### Approach 5: gVisor (runsc)

Google's user-space kernel intercepts syscalls before they reach the host kernel. 10-30% overhead on I/O-heavy workloads, minimal for compute. Good for CI/CD but not commonly used for interactive dev environments.

### Practical Recommendation

For macOS development with OrbStack/Docker Desktop: Docker Sandboxes is the most practical path if your projects need Docker. For pure container isolation without Docker-in-Docker needs, a regular devcontainer is simpler and lighter.

---

## 4. Container Persistence Strategies

### Strategy 1: Named Volumes for Specific Paths (Recommended)

Mount named volumes for directories that contain state you want to survive container rebuilds:

```json
{
  "mounts": [
    "source=project-claude-config,target=/home/user/.claude,type=volume",
    "source=project-shell-history,target=/commandhistory,type=volume",
    "source=project-gh-auth,target=/home/user/.config/gh,type=volume",
    "source=project-node-modules,target=/workspace/node_modules,type=volume",
    "source=project-tmp,target=/tmp,type=volume"
  ]
}
```

**Advantages:**
- Survives `docker compose down` and `docker compose up`
- Survives container rebuilds (image changes)
- Specific and predictable -- you know exactly what persists
- On OrbStack, volumes are fast (stored on Linux side) and accessible from macOS at `~/OrbStack/docker/`

**Disadvantage:** You must explicitly declare every path. Tools installed globally (e.g., `pip install something` or `cargo install something`) go to paths you might not have volume-mounted.

### Strategy 2: Stop/Start Instead of Remove/Create

```bash
docker stop mycontainer    # preserves ALL filesystem state
docker start mycontainer   # everything is exactly where you left it
```

The entire container filesystem (writable layer) persists. This is the simplest approach for "go to bed, come back tomorrow" workflows. Works perfectly for your use case of keeping `/tmp`, `~/`, installed tools, etc.

**Limitation:** If you rebuild the image (Dockerfile changes), you need to remove and recreate the container, losing the writable layer.

### Strategy 3: docker commit (Snapshot Approach)

```bash
docker commit mycontainer myimage:with-tools
# Later, create new container from this snapshot
docker run -it myimage:with-tools
```

**Limitation:** `docker commit` does NOT include volume data. It snapshots only the container's writable layer. Also creates large, opaque images that are hard to reproduce.

### Strategy 4: Layered Approach (Best for Your Use Case)

Combine strategies:

1. **Base image** in Dockerfile: core tools that rarely change (runtimes, CLIs, shell config)
2. **Named volumes** for: `~/.claude`, `~/.config/gh`, `/commandhistory`, `node_modules`, build caches
3. **Stop/start** for daily use -- preserves everything including ad-hoc tool installations
4. **Bind mount** for: project source code (the one directory you edit from host)
5. **Rebuild** only when the Dockerfile changes, accepting that ad-hoc tools will need reinstallation (mitigate with a `postStartCommand` script)

### Docker Sandboxes Persistence

Docker Sandboxes persist automatically until `docker sandbox rm`. All state (installed packages, Docker images, agent configuration, workspace modifications) survives across sessions. However, removing a sandbox destroys everything -- there are no separate volumes to preserve.

---

## 5. Resource Usage: Multiple Containers Sharing a Base Image

### Disk Storage: Shared Efficiently

Docker's overlay2 storage driver deduplicates image layers on disk. If 10 containers use the same `node:20` base image, that image is stored **once** on disk. Each container gets a thin writable layer (overlay "upperdir") for its modifications.

### RAM: NOT Automatically Shared

This is the critical finding for your concern about running 5-10 containers.

**What IS shared:**
- **Page cache for read-only files:** When multiple containers read the same file from a shared image layer, the Linux kernel's page cache serves it from a single copy in RAM. The overlay2 driver documentation confirms: "Multiple containers accessing the same file share a single page cache entry for that file." This is significant -- if all containers load the same Node.js binary, Python interpreter, or shared libraries from the base image, there's ONE copy in the page cache.

**What is NOT shared:**
- **Process memory:** Each container's running processes have their own private memory. If 10 containers each run a Node.js process, that's 10 separate V8 heaps.
- **Loaded shared libraries (in process space):** Although the same `libc.so` file is served from one page cache entry, once a process maps it and starts modifying pages (copy-on-write at the memory page level), modified pages are duplicated. Read-only pages (most of a shared library's code segment) remain shared via the page cache.
- **KSM (Kernel Samepage Merging):** Linux has a kernel feature that can deduplicate identical memory pages across processes, but it carries "significant performance cost" and is **not enabled by default** for Docker containers. It scans memory periodically, and the CPU overhead is usually not worth it for dev environments.

### Practical RAM Impact

For your scenario of running 5-10 containers with the same base image:

| Component | Shared? | Approximate per-container overhead |
|-----------|---------|-----------------------------------|
| Base image files on disk | Yes (overlay2) | ~0 additional |
| Node.js binary (page cache) | Yes (read-only pages) | ~0 additional |
| Python interpreter (page cache) | Yes (read-only pages) | ~0 additional |
| Shared libraries (.so files, code pages) | Mostly yes (read-only segments) | Minimal |
| Node.js V8 heap (running process) | No | 50-200MB per process |
| Python process memory | No | 30-100MB per process |
| Claude Code process (Node.js) | No | 100-300MB per process |
| Container writable layer overhead | No (but tiny) | <1MB |

**Bottom line:** If Claude Code is running in each container, you're looking at roughly 100-300MB of process memory per container that cannot be shared. The runtimes themselves (binaries, libraries) benefit from page cache sharing. For 5 containers, expect ~500MB-1.5GB of unique process memory. For 10 containers, ~1-3GB.

### Docker Sandboxes: Worse for Sharing

Because Docker Sandboxes use separate microVMs, there is **no sharing at all** -- each VM has its own kernel, its own page cache, its own everything. A microVM has a baseline overhead of ~128-256MB. Running 10 sandboxes could easily consume 3-5GB just in VM overhead before any process memory.

---

## 6. Open Source Tools for Disposable Dev Containers (Non-DevContainer-Spec)

### DevPod (loft-sh/devpod)

**What it is:** "Codespaces but open-source, client-only and unopinionated." Despite using devcontainer.json for configuration, DevPod adds significant capabilities:

- Works with any IDE via SSH (not just VS Code)
- Supports Docker, Kubernetes, cloud VMs, or any SSH target as the backend
- Client-agent architecture where DevPod deploys an SSH/gRPC agent into the container
- Can auto-detect project type and set up a dev environment without devcontainer.json
- Provider-agnostic: same `devpod up` command works whether targeting local Docker, a cloud VM, or a Kubernetes cluster

**Distinction from devcontainer spec:** While it uses devcontainer.json, it's a complete orchestration layer that works independently of VS Code. You can use it from terminal with JetBrains, Neovim, or any SSH-capable editor.

### Trail of Bits devc CLI

Already covered above, but worth highlighting as a non-spec tool:
- Purpose-built for Claude Code sandboxing
- `devc .` / `devc shell` / `devc rebuild` / `devc destroy` workflow
- Session sync between container and host
- Not tied to the devcontainer spec machinery (uses it internally but provides its own CLI)

### textcortex/claude-code-sandbox (archived, continued as "Spritz")

CLI for running Claude Code in disposable Docker containers. Copies repos in rather than mounting, creates git branches per session, monitors commits in real-time.

### agent-infra/sandbox (AIO Sandbox)

All-in-one Docker container combining browser (VNC + CDP), shell, file operations, MCP servers, VSCode Server, and Jupyter in a single container. Designed for AI agents that need browser access alongside shell access.

### Daytona

Pivoted from dev environments to AI agent infrastructure. Docker/OCI containers with native state management (stop/resume/archive). $0.067/hour per 1 vCPU. More relevant for cloud-hosted sandboxes than local development.

### E2B (e2b.dev)

Firecracker microVMs in the cloud. ~200ms startup. $0.05/hour per vCPU. Ephemeral filesystems per session. Primarily for hosted AI agent execution, not local development.

### Anthropic's sandbox-runtime (npm package)

The sandbox runtime from Claude Code's native sandboxing is available as an open-source npm package:
```bash
npx @anthropic-ai/sandbox-runtime <command-to-sandbox>
```
Uses OS-level primitives (Seatbelt on macOS, bubblewrap on Linux) for filesystem and network isolation. Not a container solution, but can sandbox individual commands or processes on the host.

---

## Key Takeaways for Your Use Case

1. **Bind mounts with OrbStack are fast enough** for your project-directory-mounted-into-container pattern. Use `consistency=delegated` and named volumes for heavy I/O paths.

2. **Stop/start containers for daily persistence, named volumes for rebuild persistence.** This gives you the "go to bed, come back" workflow without losing `/tmp` or installed tools, while also surviving occasional image rebuilds.

3. **RAM sharing is better than you might fear** -- page cache sharing means base image files aren't duplicated in memory. The real cost is per-container process memory (Claude Code itself at ~100-300MB each).

4. **Docker Sandboxes are the gold standard for isolation** but have significant overhead (no image sharing, microVM memory cost, macOS-only via Docker Desktop). For trusted personal projects where you just want to prevent accidental `rm -rf ~`, a regular devcontainer is lighter.

5. **For projects needing Docker:** either use Docker Sandboxes (which include their own Docker daemon) or investigate Sysbox if you move to a Linux-based setup. On macOS with Docker Desktop/OrbStack, Docker Sandboxes is currently the only practical option.

6. **The devcontainer-features approach** (Anthropic's `ghcr.io/anthropics/devcontainer-features/claude-code`) lets you add Claude Code to any existing devcontainer image, so you can build your ideal base image with all your tools and just layer Claude Code on top.

---

## Sources

- [Docker Sandboxes: Run Claude Code and More Safely](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/)
- [Docker Sandboxes Documentation](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandboxes Architecture](https://docs.docker.com/ai/sandboxes/architecture/)
- [Docker Sandboxes Claude Code Setup](https://docs.docker.com/ai/sandboxes/agents/claude-code/)
- [Claude Code Sandboxing Docs](https://code.claude.com/docs/en/sandboxing)
- [Anthropic's Official .devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
- [Anthropic devcontainer-features](https://github.com/anthropics/devcontainer-features)
- [Trail of Bits claude-code-devcontainer](https://github.com/trailofbits/claude-code-devcontainer)
- [textcortex/claude-code-sandbox](https://github.com/textcortex/claude-code-sandbox)
- [Code With Andrea: Run AI Agents Inside DevContainer](https://codewithandrea.com/articles/run-ai-agents-inside-devcontainer/)
- [OrbStack: Fast Container Filesystems on macOS](https://orbstack.dev/blog/fast-filesystem)
- [OrbStack Volumes & Mounts Docs](https://docs.orbstack.dev/docker/file-sharing)
- [Docker on macOS Performance 2025 Benchmarks](https://www.paolomainardi.com/posts/docker-performance-macos-2025/)
- [Sysbox (nestybox)](https://github.com/nestybox/sysbox)
- [Northflank: How to Sandbox AI Agents in 2026](https://northflank.com/blog/how-to-sandbox-ai-agents)
- [AI Sandbox Comparison 2026: E2B vs Lifo vs Daytona](https://lifo.sh/blog/ai-sandbox-comparison-2026)
- [Rivet: Reverse-Engineered Docker Sandbox MicroVM API](https://rivet.dev/blog/2026-02-04-we-reverse-engineered-docker-sandbox-undocumented-microvm-api/)
- [Docker Memory with Same Base Image (Forum)](https://forums.docker.com/t/docker-memory-usage-when-it-comes-to-the-same-base-image/116639)
- [Docker Memory Deduplication Discussion (moby/moby #7950)](https://github.com/moby/moby/issues/7950)
- [OverlayFS Storage Driver](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/)
- [agent-infra/sandbox](https://github.com/agent-infra/sandbox)
- [DevPod](https://devpod.sh/)
