# Ring-Fenced Development Environment: Research Findings

> Research conducted March 2026. Sources include official documentation, GitHub repos, community discussions, and web articles.

---

## Executive Summary

There are **four viable high-level approaches** for creating ring-fenced dev environments on your Mac, plus one emerging option not yet ready. Each involves trade-offs between isolation, developer experience, resource efficiency, and complexity.

| Approach | Isolation | DX | Resource Cost | Complexity | Maturity |
|----------|-----------|-----|---------------|------------|----------|
| **A. OrbStack Linux Machines** | Namespace (shared kernel) | Excellent | Very Low | Low | Production |
| **B. Docker Devcontainers (via OrbStack)** | Container | Very Good | Low | Low-Medium | Production |
| **C. Lima VMs** | Full VM (own kernel) | Good | Medium | Medium | Production |
| **D. Hybrid: OrbStack machine + Docker inside** | Container-in-VM | Very Good | Low-Medium | Medium | Production |
| **E. Apple Containers** | VM-per-container | Unknown | Unknown | Medium | Pre-1.0 (macOS 26+) |

**Spoiler**: Approaches A and B are the strongest candidates. The choice between them depends on whether you want "full Linux machine" (A) or "devcontainer-spec" (B) as the environment model.

---

## Approach A: OrbStack Linux Machines

**OrbStack is already installed on your Mac.** It provides "Linux machines" - lightweight Linux environments that behave like VMs but share a single underlying VM kernel (similar to WSL2 on Windows).

### How It Works
- All Linux machines share one lightweight VM using Apple Virtualization Framework
- Each machine gets isolated filesystem, user space, and init system (systemd)
- Supported distros: Ubuntu, Debian, Fedora, Arch, Alpine, others
- Create: `orb create ubuntu my-project` (< 1 minute)
- Shell: `orb -m my-project` (instant)

### Strengths

- **Resource efficiency**: Best in class. Idle machines use ~0% additional CPU. You can run dozens simultaneously. 6 machines might share ~2-6 GB total RAM.
- **Startup**: ~1-2 seconds
- **File sharing**: Bidirectional via VirtioFS. Mac files at `/mnt/mac` in Linux. Linux files accessible from Mac via `~/OrbStack/` and Finder.
- **Networking**: Each machine gets `<name>.orb.local` DNS. Services are available at localhost automatically. No manual port forwarding needed.
- **SSH agent**: Automatically forwarded. Git push/pull to GitHub works immediately.
- **VS Code/Cursor**: Works via Remote-SSH. OrbStack auto-generates SSH config.
- **Shell experience**: Full Linux - install zsh, oh-my-zsh, any tools you want.
- **Persistence**: Machines persist across reboots. Stop/start freely.
- **Provisioning**: Supports cloud-init for automated setup. Can script with `orb create` + post-setup scripts.
- **GUI file access**: Linux files visible in Finder via OrbStack tab in sidebar, and at `~/OrbStack/`.
- **Multi-arch**: Rosetta for x86_64 binaries. Can create x86_64 machines.
- **Clipboard**: Text clipboard sharing built-in.

### Weaknesses

- **Shared kernel**: All machines share one Linux kernel. Cannot run different kernel versions.
- **Closed source**: Commercial software (free for personal use, $8/mo for teams).
- **No image clipboard**: Text clipboard works, but pasting images from macOS clipboard into a terminal in a Linux machine does NOT work natively.
- **No nested KVM**: Cannot run VMs inside OrbStack machines.
- **No graphical Linux apps** by default (workarounds exist via XQuartz).
- **Less isolation than a full VM**: Namespace isolation, not hypervisor-level per machine.

### How Claude Code Would Work

1. Install Claude Code inside the OrbStack machine
2. Configure `~/.claude/settings.json` inside the machine with permissive allowlists
3. Claude Code has full autonomy within the machine's filesystem and network
4. Write-gating (git push, gh api POST, etc.) handled via Claude Code's own permission settings and/or hooks
5. Auth via `ANTHROPIC_API_KEY` env var or browser-based OAuth (copy URL from terminal, open in Mac browser)
6. MCP servers (Context7, Playwright) run inside the machine

### Fit Against Requirements

| Requirement | Status | Notes |
|------------|--------|-------|
| Full autonomy inside env | YES | Full Linux with root |
| Internet reads unrestricted | YES | Full network access |
| Internet writes gated | YES | Via Claude settings/hooks |
| Host filesystem inaccessible by default | YES | `/mnt/mac` exists but can be restricted |
| Persistent environments | YES | Survive reboots |
| 3-4+ concurrent | YES | Very lightweight |
| Fast startup | YES | ~1-2 seconds |
| Recreatable from git + base | YES | cloud-init + setup scripts |
| Cursor/VS Code | YES | Remote-SSH |
| GUI file access | YES | Finder via ~/OrbStack |
| Image sharing w/ Claude | PARTIAL | File path works, clipboard paste doesn't |
| Port forwarding | YES | Automatic |
| Playwright | YES | Headless Linux, install normally |
| Shell feels like home | YES | Full zsh + oh-my-zsh |
| Global config versioned | YES | Dotfiles in the machine, managed separately |

---

## Approach B: Docker Devcontainers (via OrbStack as Docker Runtime)

The **devcontainers spec** is an open standard for containerized dev environments. Anthropic provides an **official reference devcontainer** for Claude Code specifically designed for safe autonomous operation.

### How It Works
- A `.devcontainer/devcontainer.json` in your project defines the container environment
- VS Code/Cursor "Reopen in Container" builds and launches it
- The container runs via Docker (OrbStack provides the Docker runtime on your Mac)
- Anthropic's reference includes a firewall (`init-firewall.sh`) with default-deny outbound network

### The Anthropic Reference Devcontainer

Three files at `github.com/anthropics/claude-code/tree/main/.devcontainer`:

1. **Dockerfile**: Node.js 20, git, zsh, fzf, dev dependencies
2. **devcontainer.json**: VS Code extensions, volume mounts, settings
3. **init-firewall.sh**: iptables firewall - default-deny, whitelists only:
   - npm registry, GitHub, Claude API
   - Outbound DNS and SSH
   - `*.modelcontextprotocol.io` (for MCP)

This setup is **explicitly designed** to enable `claude --dangerously-skip-permissions` for fully unattended operation.

### Strengths

- **Official Anthropic support**: This is the recommended way to sandbox Claude Code
- **`--dangerously-skip-permissions`**: Safe to use because the container provides the safety boundary
- **Devcontainer spec**: Portable, well-documented, supported by VS Code, Cursor, JetBrains, DevPod
- **Firewall**: Network isolation beyond just filesystem isolation
- **Session persistence**: Command history and configs survive container restarts
- **Cursor integration**: Cursor has a Dev Containers extension (by Anysphere)
- **Reproducible**: Dockerfile + devcontainer.json fully define the environment
- **Port forwarding**: Declared in devcontainer.json, auto-forwarded by VS Code/Cursor
- **Dotfiles**: Spec supports dotfiles repository auto-installation

### Weaknesses

- **VS Code/Cursor coupling**: Primary workflow requires the IDE to manage the container lifecycle. CLI-only usage requires the `devcontainer` CLI tool.
- **Container, not a full VM**: Less "feels like a machine" than OrbStack Linux machines. No systemd by default (though possible).
- **Filesystem performance**: Bind mounts from macOS into Docker containers have historically been slow. Named volumes (inside the container) have native performance. On OrbStack, bind mount performance is best-in-class but still not native.
- **Anthopic's warning**: "Doesn't prevent a malicious project from exfiltrating anything accessible in the devcontainer including Claude Code credentials." Only use with trusted repos.
- **Image clipboard**: Same limitation - no image paste from macOS clipboard into terminal inside container.
- **Per-project overhead**: Each project needs its own devcontainer config. No shared "base machine" concept (though you can use a common base Docker image).
- **Recreating is slower**: Container rebuild involves pulling/building images and running setup scripts. Faster than from-scratch but slower than just starting an existing OrbStack machine.

### Community Experiences

Several developers have written about this approach:
- [Code With Andrea](https://codewithandrea.com/articles/run-ai-agents-inside-devcontainer/): "Claude Code can only affect the mounted project." Works well for code generation, terminal commands, git. IDE integration features don't work in container mode.
- [Jökull Sólberg](https://www.solberg.is/claude-devcontainer): Setup takes ~15 minutes. Persistent credentials via bind mounts. Gotcha: mounted GitHub credentials could still enable destructive repo actions.
- [claude-code-sandbox](https://github.com/textcortex/claude-code-sandbox): A PoC tool that automated this pattern - created isolated Docker containers with `--dangerously-skip-permissions`, browser UI for monitoring. **Archived Feb 2026**, successor project "Spritz" reportedly continues the concept.

### Fit Against Requirements

| Requirement | Status | Notes |
|------------|--------|-------|
| Full autonomy inside env | YES | `--dangerously-skip-permissions` |
| Internet reads unrestricted | PARTIAL | Firewall whitelists specific domains; customizable |
| Internet writes gated | YES | Firewall + Claude settings/hooks |
| Host filesystem inaccessible | YES | Container isolation |
| Persistent environments | YES | Containers persist; volumes survive rebuilds |
| 3-4+ concurrent | YES | Lightweight via OrbStack |
| Fast startup | GOOD | Starting existing container: seconds. Rebuild: minutes. |
| Recreatable from git + base | YES | devcontainer.json + Dockerfile |
| Cursor/VS Code | YES | Native devcontainer support |
| GUI file access | PARTIAL | Possible via Docker volume inspection or bind mounts |
| Image sharing w/ Claude | PARTIAL | File path works, clipboard paste doesn't |
| Port forwarding | YES | Declared in devcontainer.json |
| Playwright | YES | Install in container, headless mode |
| Shell feels like home | PARTIAL | Container shell, not a full machine. Customizable but more constrained. |
| Global config versioned | PARTIAL | Base Docker image can be shared, but each project has its own container |

---

## Approach C: Lima VMs

**Lima** (Linux Machines) is an open-source CNCF project that launches full Linux VMs on macOS using Apple Virtualization Framework.

### How It Works
- Each Lima instance is a separate, full Linux VM with its own kernel
- Uses Apple Virtualization Framework (VZ backend) for near-native performance
- VirtioFS for fast file sharing
- Automatic port forwarding via SSH tunneling
- `brew install lima`, then `limactl create/start/shell`

### Strengths

- **Full VM isolation**: Each instance has its own kernel. Strongest isolation short of running on separate hardware.
- **Open source**: CNCF project, strong community, no vendor lock-in.
- **VZ backend performance**: ~3-5 second boot, near-native CPU/memory, VirtioFS file sharing.
- **Rosetta x86_64 support**: Run x86 binaries in ARM64 VMs.
- **Full Linux**: systemd, apt/dnf, full root access. Install anything.
- **Snapshots**: Save/restore VM state (VZ backend on macOS 14+).
- **VS Code/Cursor**: SSH Remote works. Lima auto-generates SSH config.
- **Highly configurable**: YAML config for CPUs, memory, disk, mounts, provisioning.
- **Cloud-init**: Automated provisioning on VM creation.

### Weaknesses

- **Resource overhead**: Each VM is a separate process. 6 VMs at 2-4 GB each = 12-24 GB RAM.
- **More manual setup**: No built-in GUI, clipboard sharing, or DNS-based networking.
- **No clipboard**: Must use SSH workarounds (`pbcopy`/`pbpaste` over SSH).
- **Networking**: Port forwarding works but is SSH-based. No automatic DNS like OrbStack.
- **File sharing caveats**: VirtioFS is fast but has been known to have edge cases with file watchers (inotify) that some dev tools depend on.
- **GUI file access**: Need reverse SSHFS mount or manual file transfer. Less seamless than OrbStack.

### Fit Against Requirements

| Requirement | Status | Notes |
|------------|--------|-------|
| Full autonomy inside env | YES | Full VM with root |
| Internet reads unrestricted | YES | Full network access |
| Internet writes gated | YES | Via Claude settings/hooks |
| Host filesystem inaccessible | YES | VM isolation (unless you mount ~) |
| Persistent environments | YES | VMs survive reboots |
| 3-4+ concurrent | YES BUT HEAVY | 12-24 GB RAM for 6 VMs |
| Fast startup | YES | ~3-5 seconds (VZ) |
| Recreatable from git + base | YES | cloud-init + lima.yaml |
| Cursor/VS Code | YES | Remote-SSH |
| GUI file access | PARTIAL | Reverse SSHFS or manual transfer |
| Image sharing w/ Claude | PARTIAL | File path via shared mount |
| Port forwarding | YES | Automatic SSH-based |
| Playwright | YES | Full Linux, install normally |
| Shell feels like home | YES | Full Linux, full zsh |
| Global config versioned | YES | Provisioning scripts + dotfiles |

---

## Approach D: Hybrid (OrbStack Machine + Docker Inside)

Combine OrbStack Linux machines (the "base environment") with Docker devcontainers running inside them.

### How It Would Work
1. Create an OrbStack Linux machine as your persistent dev environment
2. Install Docker inside the machine
3. Use devcontainers within the machine for project-specific isolation
4. Claude Code runs inside the devcontainer with `--dangerously-skip-permissions`
5. The OrbStack machine provides the "base" (dotfiles, global tools, shell config)
6. The devcontainer provides per-project isolation + Anthropic's firewall

### Strengths
- Two layers of isolation: machine + container
- Global base config lives in the OrbStack machine (version-controlled dotfiles)
- Per-project config in devcontainer.json (committed to project repo)
- All OrbStack DX benefits (networking, file sharing, clipboard)
- Anthropic's recommended Claude Code security model

### Weaknesses
- More complexity: two layers to manage
- Docker-in-OrbStack-machine means nested container runtimes
- Possibly overkill for the actual threat model
- Adds latency to environment creation (start machine + build container)

---

## Approach E: Apple Containers (Future Option)

Apple announced **Containerization** at WWDC 2025 (June 2025). It's a Swift framework for running Linux containers as lightweight VMs on macOS.

### Current State
- **Requires macOS 26** (not yet widely available)
- **Pre-1.0**: Latest release is v0.10.0. "Minor version releases may include breaking changes."
- **Open source**: [github.com/apple/container](https://github.com/apple/container) (25k+ GitHub stars)
- **OCI compatible**: Pulls standard container images from registries

### Key Technical Detail
Each container runs in its **own lightweight VM** (not namespace isolation like Docker). This provides hardware-level isolation per container.

### Benchmarks (v0.6.0)
- CPU/memory performance: Competitive with OrbStack and Docker Desktop
- Container startup: ~0.93s (5x slower than Docker Desktop's ~0.19s, 4x slower than OrbStack's ~0.23s)
- File I/O: Significantly behind OrbStack

### Assessment
**Not ready yet.** Interesting future option that could eventually replace Docker for macOS-native containerization. Worth watching but not viable for production use today. Requires an OS version that isn't widely deployed yet.

---

## Approach F: Docker Sandboxes (Evaluated March 2026)

Docker's first-party solution (Docker Desktop 4.58+, Jan 2026) uses **microVMs, not containers**. Each sandbox gets its own lightweight VM with its own kernel and private Docker daemon. Designed specifically for AI coding agents.

### How It Works
- `docker sandbox run claude ~/my-project` creates a microVM, syncs files, starts Claude Code with `--dangerously-skip-permissions`
- Files sync bidirectionally via **copying** (not volume mounts), preserving absolute paths
- Outbound internet through an HTTPS filtering proxy that auto-injects credentials (API keys never enter the sandbox)
- Network allow/deny policies available
- Custom templates via Dockerfile extending `docker/sandbox-templates:claude-code`
- Sandboxes persist until explicitly `docker sandbox rm`'d

### Strengths
- **Strongest isolation**: Hypervisor-level, private Docker daemon, private kernel
- **Docker-in-Docker works**: Each sandbox has its own Docker daemon
- **Credential injection via proxy**: API keys stay on host, never stored in sandbox
- **Disposable**: Delete and recreate in seconds
- **`--dangerously-skip-permissions` by default**: The sandbox IS the safety boundary
- **`docker sandbox save`**: Snapshot running sandboxes as reusable templates

### Why It Was Ruled Out (as of March 2026)

**Dealbreaker: No port forwarding.** Services running inside sandboxes cannot be accessed from the host browser. Docker's blog post (Jan 2026) lists "port exposure to host device" under "What's Next" (not yet implemented). Release notes through 4.64.0 (March 2026) show no change. Rules out any web development workflow.

**4GB RAM hard cap.** Not configurable, no swap, no workaround. OOM kills reported under heavy workloads (webpack, Rust compilation, Java). Community issue #121 has significant concern.

**File sync corrupts `.git/index`.** Bidirectional sync of binary files causes git to segfault on the host (issue #62). No `.sandboxignore` or exclude mechanism exists (issue #163).

**Claude config wiped on start.** `CLAUDE.md`, `settings.json`, `claude.json` placed in `/home/agent/.claude/` via Dockerfile are blown away when the container starts (issue #167). Cannot pre-configure Claude Code.

**Requires Docker Desktop.** Not compatible with OrbStack. Would need to switch from the already-installed OrbStack.

**No shared images/layers between sandboxes.** Each microVM has its own isolated storage. Disk and memory grow linearly per sandbox.

### Worth Revisiting When
- Port forwarding ships
- RAM becomes configurable
- File sync gets exclude patterns and `.git` corruption is fixed
- Claude config persistence is fixed

### Sources
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandboxes architecture](https://docs.docker.com/ai/sandboxes/architecture/)
- [Docker blog: Run Claude Code Safely](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/)
- [Docker Desktop release notes](https://docs.docker.com/desktop/release-notes/)

---

## Other Tools & Approaches Evaluated (March 2026)

### Trail of Bits `devc` CLI
Purpose-built for per-project Claude Code sandboxing. Ubuntu 24.04 base, Node 22, Python 3.13, uv, persistent named volumes for `~/.claude` and `~/.config/gh`. Simple workflow: `devc .` / `devc shell` / `devc rebuild` / `devc destroy`. Worth referencing as a pattern even if rolling our own. [GitHub](https://github.com/trailofbits/claude-code-devcontainer)

### Anthropic `devcontainer-features`
A Dev Container Feature for installing Claude Code into any devcontainer: `"ghcr.io/anthropics/devcontainer-features/claude-code:1": {}`. Can be combined with any base image. [GitHub](https://github.com/anthropics/devcontainer-features)

### Pere Villega's Incus + OrbStack approach
Uses Incus system containers (full OS instances with systemd) running inside an OrbStack VM, with btrfs CoW snapshots for instant environment cloning. Strong isolation model but **no file syncing to host** by design - all interaction through git. Interesting ideas: ssh-agent forwarding (keys never on disk), Squid-based network egress filtering, pre-built language stack "golden images". Not suitable for our use case (need local file access). [Blog post](https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/)

---

## Cross-Cutting Concerns

### Image Paste / Clipboard Sharing with Claude Code

This is **the hardest requirement to fully satisfy** with any container/VM approach.

**The Problem:**
- Claude Code supports `Ctrl+V` image paste from clipboard in a local terminal
- When Claude Code runs inside a container/VM, the macOS clipboard is not directly accessible
- Terminal protocols (including Ghostty, which you use) do not support transmitting image data over SSH/remote connections
- [Ghostty issue #10478](https://github.com/ghostty-org/ghostty/discussions/10478): Feature request for clipboard image paste. Not yet implemented.
- [Ghostty issue #10517](https://github.com/ghostty-org/ghostty/discussions/10517): SSH image paste support - not available.
- iTerm2's Ctrl+V image paste into Claude Code [reportedly works ~50-60% of the time](https://github.com/anthropics/claude-code/issues/29365) even locally.

**Workarounds:**
1. **File path reference**: Save screenshot to shared filesystem, reference with `@/path/to/image.png` in Claude Code. OrbStack's file sharing makes this relatively easy (save to Mac, access via `/mnt/mac/...` in the machine).
2. **Claude Code Remote Control**: Claude Code has a "Remote Control" feature where you control a running session from a browser. The browser UI *should* support image paste. Session runs locally (or in the container), browser is just a view.
3. **Quick screenshot script**: A one-liner on your Mac that saves the clipboard image to a known path accessible from the container. E.g.: `pngpaste /tmp/screenshot.png` (install via `brew install pngpaste`). The shared filesystem makes it immediately available inside the container/VM.
4. **Switch terminals**: Keep a local Claude Code session for image-heavy interactions; use the ring-fenced one for autonomous work.

**Realistic assessment**: This won't be as seamless as your current workflow (screenshot -> drag into Ghostty). The fastest realistic flow would be: take screenshot -> run a keyboard shortcut that saves it to a shared folder -> reference the path in Claude Code. This adds ~5 seconds vs the current ~2 seconds.

### Claude Code Permission Gating (Read vs Write)

**The architecture for gating writes** is well-supported by Claude Code regardless of which environment approach you choose:

**Layer 1: Container/VM isolation** (the ring-fence itself)
- Claude Code cannot access host filesystem
- Cannot modify anything outside the environment

**Layer 2: Claude Code permission rules** (`settings.json`)
- Deny `git push`, `gh pr create`, `gh issue create`, etc.
- Allow everything else
- Limitation: Glob patterns can't distinguish `gh api -X GET` from `gh api -X POST`

**Layer 3: Claude Code hooks** (the precision tool)
- `PreToolUse` hooks fire before every tool call
- Receive the full command as JSON on stdin
- Can parse arguments and make allow/deny decisions
- **This is the correct mechanism for read-vs-write gating**
- Example: A bash script that allows `gh api` by default but blocks if it sees `-X POST|PUT|DELETE|PATCH`

**Layer 4: Network firewall** (optional, defense-in-depth)
- The Anthropic reference devcontainer includes iptables rules
- Default-deny outbound with domain whitelisting
- Useful if running `--dangerously-skip-permissions`

For your use case (not using `--dangerously-skip-permissions`, just wanting fewer prompts), **Layers 1-3 are sufficient**. You'd configure Claude Code's settings.json inside the environment to allow most things freely, with specific deny rules and hooks for write operations.

### Playwright

Works in all approaches. Playwright provides official Docker images and supports headless Linux operation. In OrbStack Linux machines or Lima VMs, install normally:
```bash
npx playwright install --with-deps
```
The `playwright-cli` MCP server should work inside any of these environments.

### Tauri Projects (Special Case)

Tauri dev servers launch native macOS apps, which cannot run inside Linux containers/VMs. Options:
1. **Mount the project directory** from the OrbStack machine/container onto the Mac via OrbStack's file sharing. Claude Code works on code in the machine; you run `cargo tauri dev` locally on the Mac.
2. **Keep Tauri projects local** on the Mac with the current (non-ring-fenced) workflow.
3. Tauri v2 has improved headless/testing support that may help.

This is a known limitation of any Linux-based approach. Since it's a minority of your projects, option 1 seems reasonable.

### Base Template / Global Config

All approaches support a "common base" concept:

| Approach | Base Template Mechanism |
|----------|------------------------|
| **OrbStack machine** | A setup script (+ dotfiles repo) that provisions a fresh machine. Or: create one "template" machine and `orb clone` it (if supported), otherwise script it. |
| **Devcontainer** | A shared base Docker image pushed to a registry. All projects `FROM` this image. |
| **Lima** | A `lima.yaml` template + cloud-init provisioning script. |

For any approach, the global config (dotfiles, Claude Code settings, global tools) should be in a version-controlled repo, separate from individual project repos.

---

## Tool Comparison Matrix

| Factor | OrbStack Machines | Devcontainers (OrbStack Docker) | Lima VMs |
|--------|-------------------|-------------------------------|----------|
| **Already installed** | YES (OrbStack) | YES (OrbStack provides Docker) | No (brew install lima) |
| **Isolation level** | Namespace | Container | Full VM |
| **Resource for 6 envs** | ~2-6 GB shared | ~3-8 GB (containers are light) | ~12-24 GB |
| **Startup time** | ~1-2s | ~2-5s (existing) / minutes (rebuild) | ~3-5s |
| **Shell experience** | Full Linux machine | Container shell (customizable) | Full Linux machine |
| **File sharing perf** | Excellent (VirtioFS) | Good (volumes) / OK (bind mounts) | Excellent (VirtioFS) |
| **Port forwarding** | Automatic (DNS) | Declared in devcontainer.json | Automatic (SSH) |
| **Cursor integration** | Remote-SSH | Dev Containers extension | Remote-SSH |
| **Finder access to files** | ~/OrbStack/ | Docker volume inspect / bind mount | Reverse SSHFS |
| **Clipboard (text)** | YES | Via terminal | SSH workaround |
| **Claude Code sandbox story** | Settings + hooks | Official devcontainer + `--dangerously-skip-permissions` | Settings + hooks |
| **Global base template** | Setup script / dotfiles | Base Docker image | lima.yaml + cloud-init |
| **Open source** | No (free personal) | Spec is open, Docker image is yours | Yes (CNCF) |
| **Anthropic-endorsed** | No | YES (official devcontainer) | No |
| **Learning curve** | Low | Low-Medium | Medium |

---

## Recommendation

### Short version (updated March 2026)

**Per-project Docker containers via OrbStack**, with a shared custom base image containing all dev tools. Project directories bind-mounted from the host so files are editable locally in Cursor/Finder/terminal. Claude Code runs inside each container with `--dangerously-skip-permissions` (the container IS the safety boundary). Containers are disposable but persistent across sessions via stop/start.

### Why this approach

1. **Disposable per-project containers.** Each project gets its own container. If Claude does something destructive, destroy it and recreate from the base image + project repo. No impact on other projects.

2. **Shared base image.** A single Dockerfile defines all global tooling (runtimes, CLIs, Claude Code config, shell setup). All project containers share this base. Disk layers are shared via overlay2. Read-only files (binaries, libraries) share page cache in RAM.

3. **Local file access.** Project directories are bind-mounted from `~/dev/my-project` into the container. Edit in Cursor, commit in Cursor's git UI, browse in Finder - all locally. Claude Code inside the container reads/writes the same files.

4. **OrbStack is already installed** and provides the best bind mount performance on macOS (75-95% native via VirtioFS). Automatic port forwarding, lightweight, excellent DX.

5. **`--dangerously-skip-permissions`** is safe because the container boundary prevents host filesystem access and credential leakage. Write-gating for external services (git push, gh api POST) handled via Claude Code hooks inside the container.

6. **RAM overhead is manageable.** Per-container process memory is ~100-300MB (Claude Code). For 5 containers that's ~500-1.5GB unique memory. Base image files benefit from page cache sharing.

### Persistence model

- **Daily use**: `docker stop` / `docker start` - preserves everything (installed tools, `/tmp`, working state)
- **Rebuild-safe**: Named volumes for `~/.claude`, `~/.config/gh`, shell history survive container rebuilds
- **Project source**: Bind-mounted from host - always safe, never inside the container
- **Destroy & recreate**: Base image + project repo + setup scripts = full recreation

### What this gives up

- No Docker-in-Docker (projects that need Docker themselves would need a different approach - keep locally or use Docker Sandboxes when they mature)
- Container shell won't feel identical to local Mac shell (but this matters less now - most shell work happens locally on the Mac, the container is primarily for Claude Code)
- No hypervisor-level isolation (container isolation via Linux namespaces, not separate kernel). Acceptable since the threat model is "prevent accidental damage to host", not "defend against malicious code"

### The image paste problem

This is the one area where no approach fully satisfies the requirement. The realistic mitigation:

1. Install `pngpaste` on your Mac: `brew install pngpaste`
2. Set up a keyboard shortcut (via macOS Shortcuts, Raycast, or similar) that runs: `pngpaste ~/OrbStack/<machine-name>/home/danny/screenshot.png`
3. In Claude Code inside the machine: `@~/screenshot.png`

This adds a few seconds vs your current workflow. Alternatively, Claude Code's Remote Control feature (controlling the session from a browser) may support image paste through the web UI.

---

## Sources

### Official Documentation
- [OrbStack Linux machines docs](https://docs.orbstack.dev/machines/)
- [OrbStack architecture](https://docs.orbstack.dev/architecture)
- [Claude Code devcontainer docs](https://code.claude.com/docs/en/devcontainer)
- [Claude Code security docs](https://code.claude.com/docs/en/security)
- [Anthropic reference devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Containers spec](https://containers.dev/)
- [Lima](https://github.com/lima-vm/lima)
- [Apple container tool](https://github.com/apple/container)

### Articles & Community
- [How to Safely Run AI Agents Inside a DevContainer](https://codewithandrea.com/articles/run-ai-agents-inside-devcontainer/) - Code With Andrea
- [Running Claude Code Safely in Devcontainers](https://www.solberg.is/claude-devcontainer) - Jökull Sólberg
- [Claude Code --dangerously-skip-permissions: Safe Usage Guide](https://www.ksred.com/claude-code-dangerously-skip-permissions-when-to-use-it-and-when-you-absolutely-shouldnt/)
- [Apple Containers vs Docker Desktop vs OrbStack](https://www.repoflow.io/blog/apple-containers-vs-docker-desktop-vs-orbstack) - Repoflow
- [OrbStack vs Docker Desktop](https://orbstack.dev/docs/compare/docker-desktop) - OrbStack
- [Docker on macOS is still slow?](https://www.paolomainardi.com/posts/docker-performance-macos-2025/) - Paolo Mainardi
- [DevPod maintenance status](https://github.com/loft-sh/devpod/issues/1915)
- [claude-code-sandbox](https://github.com/textcortex/claude-code-sandbox) (archived)
- [Ghostty image paste discussion](https://github.com/ghostty-org/ghostty/discussions/10478)
- [Ghostty SSH image paste](https://github.com/ghostty-org/ghostty/discussions/10517)
- [Claude Code image paste iTerm2 bug](https://github.com/anthropics/claude-code/issues/29365)

### Docker Sandboxes & Community Tools (March 2026)
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandboxes architecture](https://docs.docker.com/ai/sandboxes/architecture/)
- [Docker blog: Run Claude Code Safely](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/)
- [Trail of Bits claude-code-devcontainer](https://github.com/trailofbits/claude-code-devcontainer)
- [Anthropic devcontainer-features](https://github.com/anthropics/devcontainer-features)
- [Pere Villega: AI Sandbox for Coding Agents](https://perevillega.com/posts/2026-03-03-ai-sandbox-coding-agents/)
- [OrbStack filesystem performance](https://orbstack.dev/blog/fast-filesystem)

### Tools Evaluated but Not Recommended
- **DevPod**: Was promising ("Codespaces but open-source") but [effectively unmaintained since mid-2025](https://github.com/loft-sh/devpod/issues/1915). Community fork exists but uncertain future.
- **Coder**: Enterprise-focused, requires a server component. Overkill for single-user local use.
- **Gitpod**: Organizational uncertainty. Rebranded to "Ona". Self-hosted option deprecated.
- **UTM**: GUI-first VM app. Not suitable for headless dev environments.
- **Vagrant**: Declining. Apple Silicon support via VirtualBox is slow. Lima/OrbStack are better.
- **Multipass**: Ubuntu-only VMs. Fine but less featured than Lima.
- **Nix/devenv.sh/Devbox**: Excellent for reproducible dependencies but provide NO filesystem/process isolation. They modify your PATH, not your environment boundary. Could be used *inside* a container/VM for dependency management, but don't solve the ring-fencing problem on their own.
- **Docker Sandboxes**: Excellent isolation model (microVMs) but not mature enough as of March 2026. No port forwarding (can't preview web apps), 4GB RAM hard cap, file sync corrupts `.git/index`, no sync excludes, Claude config wiped on start, requires Docker Desktop (not OrbStack). Worth revisiting when port forwarding and configurable resources ship.
