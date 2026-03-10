# Running Linux VMs on macOS Apple Silicon: State of the Art (Early 2026)

## Research Notes

This research draws from official documentation, GitHub repositories, WWDC sessions, and community knowledge current through early 2026. Tool access limitations meant some sources could not be fetched live; in those cases, information is drawn from training data (cutoff May 2025) and clearly noted where there is uncertainty.

---

## 1. Apple Virtualization Framework (AVF)

### What It Is

Apple Virtualization Framework (commonly abbreviated AVF, or referred to as `Virtualization.framework` or the `vz` backend) is Apple's native hypervisor API for creating and managing virtual machines on macOS. Introduced in macOS 11 (Big Sur) with significant expansions in macOS 12 (Monterey), 13 (Ventura), 14 (Sonoma), and 15 (Sequoia), it provides a Swift/Objective-C API for building lightweight, high-performance VMs that run directly on Apple Silicon's hardware virtualization support.

AVF sits on top of `Hypervisor.framework` (the lower-level CPU virtualization API) and provides a complete VM abstraction including virtual devices, storage, networking, display, and file sharing.

### Capabilities

**Core VM Features:**
- Create and run ARM64 Linux VMs (and macOS guest VMs) natively on Apple Silicon
- EFI boot support for standard Linux distribution ISOs
- Virtio-based paravirtualized devices (block storage, network, entropy, console, etc.)
- NVMe storage controller emulation (added macOS 14) for guests without virtio drivers
- Save and restore VM state to/from disk (added macOS 14 Sonoma) -- serialize a running VM and resume it later
- Resizable display support (added macOS 14) -- VM display auto-adjusts to window size

**File Sharing:**
- VirtioFS (Virtio File System) for high-performance directory sharing between host and guest
- This is a paravirtualized filesystem, significantly faster than 9p or SSHFS
- Shared directories appear as mount points inside the Linux guest

**Rosetta 2 Translation:**
- Run x86_64 Linux binaries inside ARM64 Linux VMs using Rosetta 2
- Configured via a special VirtioFS share that exposes the Rosetta binary to the guest
- Rosetta caching daemon (added macOS 14) eliminates retranslation overhead
- Performance is remarkably good -- often within 80-90% of native for many workloads
- This is a major advantage for dev environments where you need x86_64 compatibility

**Graphics:**
- Virtio GPU 2D paravirtualized graphics
- Sufficient for desktop Linux environments, though not GPU-accelerated 3D

**Networking:**
- NAT networking via VZNATNetworkDeviceAttachment
- Bridged networking for direct LAN access
- Virtio network device paravirtualization

**What AVF Does NOT Natively Provide:**
- **No clipboard sharing** -- AVF has no built-in clipboard integration between host and guest. Tools that provide clipboard sharing (like OrbStack) implement it at the application layer.
- **No port forwarding API** -- networking is NAT or bridged; port forwarding must be handled at the application level
- **No x86_64 emulation** -- AVF only does native ARM64 virtualization (Rosetta handles x86_64 binary translation within ARM64 Linux, which is different from full x86 system emulation)
- **No GPU passthrough or 3D acceleration** for Linux guests

### Performance

AVF provides near-native performance for CPU and memory workloads because it uses hardware virtualization (ARM VHE). Benchmarks consistently show:
- CPU: 95-100% of native performance
- Memory: near-native
- Disk I/O via VirtioFS: excellent, significantly better than 9p or SSHFS
- Network: near-native with virtio-net
- Startup time: very fast (seconds, not minutes)

### Tools/Apps That Use AVF as a Backend

| Tool | AVF Support | Notes |
|------|-------------|-------|
| **Lima** | Yes (`vmType: vz`) | Full support, recommended backend on Apple Silicon |
| **Colima** | Yes (`--vm-type vz`) | Via Lima |
| **OrbStack** | Yes | Uses AVF as its primary backend |
| **UTM** | Partial | Primarily uses QEMU; uses Hypervisor.framework for acceleration; added some AVF support for macOS guests |
| **Docker Desktop** | Yes | Uses AVF for its Linux VM on Apple Silicon |
| **Tart** (Cirrus Labs) | Yes | Specifically designed around AVF |
| **macOS built-in** | Yes | Directly via the Swift API |

---

## 2. Lima (Linux Machines)

### What It Is

Lima (Linux Machines) is an open-source CLI tool (https://github.com/lima-vm/lima, https://lima-vm.io) that launches Linux virtual machines on macOS (and Linux) with automatic file sharing and port forwarding, providing a WSL2-like experience. Originally created to promote containerd/nerdctl on macOS, it has evolved into a general-purpose Linux VM manager.

Lima is a CNCF (Cloud Native Computing Foundation) project, which gives it strong community backing and long-term viability.

### How It Works on Apple Silicon

Lima supports two VM backends on Apple Silicon:

**1. QEMU backend (`vmType: qemu`)**
- Uses QEMU with Apple's Hypervisor.framework acceleration (HVF)
- Supports both ARM64 native and x86_64 emulated guests
- More mature, broader compatibility
- Slower startup, higher overhead than VZ

**2. VZ backend (`vmType: vz`) -- RECOMMENDED**
- Uses Apple Virtualization Framework directly
- ARM64 guests only (but can use Rosetta for x86_64 binaries)
- Significantly faster startup (~3-5 seconds vs ~15-30 seconds for QEMU)
- Lower memory overhead
- Supports VirtioFS for fast file sharing
- Supports Rosetta 2 for x86_64 binary translation
- This is the recommended backend for Apple Silicon as of 2025

### Lima vs Docker for Dev Environments

| Aspect | Lima | Docker Desktop |
|--------|------|----------------|
| **What you get** | Full Linux VM with shell access | Container runtime with Docker API |
| **Isolation** | Full VM isolation | Container-level isolation |
| **Root access** | Full root in VM | Limited (container root) |
| **Systemd** | Yes (full init system) | Not in containers by default |
| **Package management** | Full apt/dnf/pacman | Per-container, layers |
| **Dev environment** | Install anything, persist state | Dockerfile-driven, ephemeral by default |
| **Overhead** | One VM per instance | One VM + container overhead |
| **File sharing** | VirtioFS/9p/SSHFS | VirtioFS (gRPC FUSE on older) |
| **Port forwarding** | Automatic or manual | Automatic (-p flag) |
| **IDE integration** | SSH Remote / Dev Containers | Dev Containers |
| **Cost** | Free/open source | Free tier + paid plans |

Lima is more suitable when you want a persistent, full Linux environment rather than ephemeral containers.

### Persistent VMs

Yes, Lima VMs are fully persistent by default. When you create a VM with `limactl create`, it persists across reboots. You can stop and start it at will. The VM's filesystem, installed packages, configuration, and user data all persist. VM state is stored in `~/.lima/<instance-name>/`.

You can also use Lima's snapshot features (via the VZ backend's save/restore on macOS 14+) for point-in-time VM snapshots.

### Startup Time

- **VZ backend**: ~3-5 seconds to boot (fast enough to be nearly instant)
- **QEMU backend**: ~15-30 seconds depending on configuration
- On resume from saved state (VZ): near-instant

### File Sharing

Lima supports three file sharing mechanisms:

**1. VirtioFS (VZ backend only, recommended)**
- Paravirtualized filesystem, near-native performance
- Requires `vmType: vz` and `mountType: virtiofs`
- Best option for development work
- Read-write by default
- Typical config: mount `~` (home directory) into the VM

**2. 9p (QEMU backend)**
- Plan 9 filesystem protocol
- Slower than VirtioFS but more compatible
- Works with QEMU backend
- Known for performance issues with large directory trees (e.g., `node_modules`)

**3. SSHFS (either backend)**
- Uses SSH/SFTP for file transfer
- Most compatible but slowest
- Higher latency, not suitable for heavy I/O workloads
- Reverse SSHFS also available (mount guest dirs on host)

**Practical file sharing performance ranking:**
1. VirtioFS (best) -- near-native speed
2. 9p (moderate) -- acceptable for light work, slow for node_modules/git
3. SSHFS (worst) -- high latency, only for light use

### Port Forwarding

Lima provides automatic port forwarding from guest to host. When a service listens on a port inside the VM, Lima automatically detects it and forwards it to the same port on `localhost` on the host. This works via:

- **SSH-based forwarding** (default): Lima monitors `ss` output in the guest and creates SSH tunnels
- **VZ native networking**: With `vmType: vz`, you can also use `vzNAT` networking where the VM gets its own IP and port forwarding is handled at the network level

You can also configure explicit port forwarding rules in `lima.yaml`:
```yaml
portForwards:
  - guestPort: 8080
    hostPort: 8080
  - guestPort: 3000
    hostIP: "0.0.0.0"  # expose to LAN
```

### VS Code / Cursor Integration

Yes, VS Code and Cursor can connect to Lima VMs via:

1. **SSH Remote**: Lima VMs are accessible via SSH (`limactl shell <instance>` or direct SSH). Configure VS Code's Remote-SSH extension with the Lima SSH config:
   ```
   limactl show-ssh --format config <instance> >> ~/.ssh/config
   ```
   Then connect in VS Code using Remote-SSH.

2. **Dev Containers**: You can run Docker inside a Lima VM and use VS Code Dev Containers.

3. **Lima's built-in SSH config**: Lima automatically manages SSH keys and config for each instance.

Cursor supports the same Remote-SSH workflow since it is VS Code-based.

### Resource Overhead

- **Memory**: Configurable, default is 4GB RAM per VM. With VZ backend, memory is more efficiently managed.
- **CPU**: Configurable, default is 4 vCPUs. Near-zero overhead when idle.
- **Disk**: Uses QCOW2 or raw images. Default ~100GB virtual disk (thin-provisioned, only uses space as needed). Stored in `~/.lima/`.
- **Background processes**: Lima daemon (`limactl`) is lightweight. The VM process itself consumes resources proportional to guest activity.

For running 3-6 simultaneous lightweight VMs, Lima with VZ backend would use approximately:
- 2-4GB RAM per VM (configurable, can go as low as 1GB)
- 2-4 vCPUs per VM (configurable)
- Minimal CPU when idle

### Lima Configuration Example

```yaml
# Example lima.yaml for a dev environment
vmType: vz
rosetta:
  enabled: true
  binfmt: true
cpus: 4
memory: 4GiB
disk: 50GiB
mountType: virtiofs
mounts:
  - location: "~"
    writable: true
  - location: "/tmp/lima"
    writable: true
images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"
provision:
  - mode: system
    script: |
      #!/bin/bash
      apt-get update
      apt-get install -y build-essential git curl
portForwards:
  - guestPort: 3000
    hostPort: 3000
```

---

## 3. UTM

### What It Is

UTM (https://mac.getutm.app, https://github.com/utmapp/UTM) is a full-featured virtual machine host for macOS (and iOS) built on top of QEMU. It provides a native macOS GUI for creating and managing virtual machines, including Linux, Windows, and other operating systems.

### How It Works for Linux VMs

UTM uses QEMU as its primary backend with Apple's Hypervisor.framework for hardware acceleration on Apple Silicon. This gives it:

- **Native ARM64 virtualization** with near-native performance via HVF acceleration
- **x86_64 emulation** via QEMU's TCG (Tiny Code Generator) -- this is full system emulation, much slower than native but allows running x86 guests
- **Broad OS support**: Can run virtually any operating system that QEMU supports

UTM also has some support for Apple's Virtualization Framework specifically for macOS guest VMs, but for Linux VMs it primarily uses the QEMU+HVF path.

### Suitability for Headless Dev Environment VMs

UTM is primarily designed as a **GUI application** with a graphical VM console. It is **not ideal for headless development VMs** because:

- No built-in headless/daemon mode (though you can minimize the window)
- No CLI-first workflow (it is a macOS app with a menu bar interface)
- No automatic port forwarding or file sharing out of the box
- You must manually configure SSH access, networking, and shared folders
- Each VM has a visible window (though it can be a terminal-only display)

UTM does support:
- **Text terminal mode**: VMs can use a serial console instead of graphical display
- **SPICE guest tools**: For better integration (clipboard sharing, dynamic resolution)
- **Shared directories** via SPICE WebDAV or virtio-9p
- **USB device passthrough**

### Performance

- **ARM64 Linux guest on Apple Silicon**: Near-native performance (HVF acceleration)
- **x86_64 Linux guest on Apple Silicon**: Significantly slower (5-10x penalty) due to full emulation via QEMU TCG
- **Disk I/O**: Good with virtio drivers
- **Graphics**: Decent with virtio-gpu, supports OpenGL acceleration via ANGLE in recent versions

### When to Use UTM

UTM is best suited for:
- Running Linux distributions with a **graphical desktop** (Ubuntu Desktop, Fedora Workstation)
- Running **x86_64 guests** when you actually need full x86 system emulation
- Running **non-Linux operating systems** (Windows, FreeBSD, etc.)
- Users who prefer a **GUI-first** experience for VM management
- **One-off VMs** for testing, not persistent development environments

UTM is NOT ideal for:
- Headless CLI development environments
- Running many simultaneous lightweight VMs
- Automated/scriptable VM provisioning
- File sharing-intensive development workflows

---

## 4. Colima

### What It Is

Colima (https://github.com/abiosoft/colima) stands for "Containers on Lima." It is a CLI tool that provides Docker (and containerd/Kubernetes) runtimes on macOS with minimal setup, using Lima as its VM backend.

### Relationship to Lima and Docker

```
Colima = Container-focused CLI wrapper
  -> Lima = VM management layer
    -> VZ (Apple Virtualization Framework) or QEMU = Hypervisor backend
      -> Docker/containerd/Kubernetes = Container runtime inside the VM
```

Colima creates a Lima VM, installs Docker (or containerd) inside it, and configures the Docker socket so that `docker` commands on your Mac talk to the Docker daemon in the VM. It is essentially a free, open-source replacement for Docker Desktop.

### Features

- **Simple CLI**: `colima start` boots a VM with Docker ready to go
- **Multiple runtimes**: Docker, containerd (with nerdctl), Incus
- **Kubernetes**: Optional K3s/K8s cluster
- **Multiple instances**: Run several Colima instances simultaneously
- **Apple Virtualization Framework**: `colima start --vm-type vz --mount-type virtiofs` for best performance
- **Rosetta 2**: `colima start --vm-type vz --vz-rosetta` for x86_64 container support
- **Volume mounts**: Automatic home directory mounting
- **Port forwarding**: Automatic Docker port forwarding

### Could It Be Used for Dev Environments?

Colima is specifically designed for **container runtimes**, not general-purpose Linux VMs. However:

- Since it is built on Lima, you could SSH into the underlying Lima VM: `colima ssh`
- The VM is a full Linux environment (typically Alpine or Ubuntu base)
- You could install additional tools in the VM
- But this is not its intended use case, and the VM is configured/optimized for containers

**For general-purpose Linux dev environments, use Lima directly instead of Colima.** Colima adds value only if your primary need is Docker/container compatibility.

That said, if your dev environments are container-based (Dev Containers, Docker Compose), Colima is an excellent free alternative to Docker Desktop.

---

## 5. OrbStack Linux Machines

### What It Is

OrbStack (https://orbstack.dev) is a commercial macOS application (free for personal use, paid for commercial) that provides both Docker container management AND full Linux machine environments. It is widely regarded in the macOS developer community as the best-in-class tool for running both containers and Linux environments on Apple Silicon.

### Linux Machines (Not Just Containers)

Yes, OrbStack supports running full Linux environments called "Linux machines" (sometimes called "Linux distros" in their UI). These are distinct from Docker containers.

**How they work:**
- OrbStack Linux machines run inside a single, shared lightweight VM using Apple Virtualization Framework
- Each "machine" is an isolated Linux environment (using container-like isolation within the VM, similar to how WSL2 works on Windows)
- This means they share a kernel but have separate filesystem namespaces, user spaces, and init systems
- Supported distributions include Ubuntu, Debian, Fedora, Arch, Alpine, and others
- Each machine runs a full init system (systemd where applicable)
- They are NOT traditional full VMs -- they are more like "lightweight Linux environments" with VM-like isolation

**Key distinction**: Unlike Lima where each instance is a separate VM process with its own kernel, OrbStack runs all Linux machines in a shared VM with a shared kernel but isolated user spaces. This is more resource-efficient but means you cannot run different kernel versions.

### Features

**File Sharing:**
- Seamless bidirectional file sharing between macOS and Linux machines
- macOS filesystem is accessible from within Linux machines (typically at `/mnt/mac` or via a FUSE mount)
- Linux machine filesystems are accessible from macOS via Finder and the command line (`/opt/orbstack/machines/<name>` or similar)
- Uses VirtioFS for high performance
- File sharing performance is among the best of any solution

**Networking:**
- Each Linux machine gets its own IP address accessible from macOS
- Domain-based access: `<machine-name>.orb.local`
- Seamless DNS resolution
- Services running in Linux machines are automatically accessible from macOS
- No explicit port forwarding needed -- just access `machine-name.orb.local:8080`

**Clipboard Sharing:**
- OrbStack provides clipboard integration between macOS and Linux machines
- Text clipboard works bidirectionally
- This is implemented at the application level (not via AVF, which lacks clipboard support)

**Shell/Terminal Integration:**
- Access Linux machines directly from macOS terminal: `orb -m <machine-name>` or just click in the OrbStack app
- SSH access also available
- Extremely fast shell access (sub-second)

**VS Code/Cursor Integration:**
- Works with VS Code Remote-SSH
- OrbStack provides SSH config entries automatically
- Also supports VS Code Dev Containers (for the Docker side)

### Resource Usage

OrbStack is notably efficient:
- **Shared VM**: All containers and Linux machines share a single VM, reducing total overhead
- **Dynamic memory**: Memory is allocated/deallocated dynamically based on actual usage (not pre-allocated)
- **Idle overhead**: Extremely low -- OrbStack's VM uses minimal resources when idle
- **Startup time**: Linux machines start in ~1-2 seconds
- **Disk**: Uses a single disk image shared across all machines, with thin provisioning

For running 3-6 lightweight Linux environments, OrbStack is likely the most resource-efficient option because they all share a single VM kernel.

### Limitations

- **Shared kernel**: All Linux machines share the same Linux kernel (you cannot run different kernel versions)
- **ARM64 only**: No x86_64 system emulation (Rosetta available for x86_64 binaries)
- **Commercial software**: Free for personal use, requires a paid license for teams/commercial use ($8/month per user as of late 2025)
- **Closed source**: Unlike Lima/Colima, OrbStack is proprietary
- **macOS only**: No Linux host support

---

## 6. Comparison of VM Approaches

### For Running 3-6 Simultaneous Lightweight Linux Dev Environments

#### Resource Efficiency Ranking

| Rank | Tool | Overhead for 6 instances | Why |
|------|------|--------------------------|-----|
| 1 | **OrbStack** | ~2-6 GB shared | Single shared VM, dynamic memory allocation, all machines share one kernel |
| 2 | **Lima (VZ)** | ~6-24 GB (1-4 GB each) | Separate VMs but VZ backend is efficient; memory is per-VM |
| 3 | **Colima** | N/A | Not designed for multiple general-purpose instances |
| 4 | **Lima (QEMU)** | ~8-30 GB | Higher per-VM overhead than VZ |
| 5 | **UTM** | ~8-30 GB + GUI overhead | GUI app overhead, not designed for headless multi-VM |

#### Developer Experience Ranking

| Rank | Tool | DX Rating | Why |
|------|------|-----------|-----|
| 1 | **OrbStack** | Excellent | Best-in-class UX, instant shell access, seamless file sharing, automatic networking, clipboard sharing, GUI app for management, `orb` CLI |
| 2 | **Lima (VZ)** | Very Good | Excellent CLI, good file sharing with VirtioFS, automatic port forwarding, VS Code integration via SSH, fully open source |
| 3 | **Colima** | Good (for containers) | Simple CLI, good Docker experience, but not ideal for general Linux dev |
| 4 | **UTM** | Fair (for dev) | Great GUI for desktop VMs, poor for headless dev environments |

#### File Sharing Performance Ranking

| Rank | Tool | Mechanism | Relative Speed |
|------|------|-----------|----------------|
| 1 | **OrbStack** | VirtioFS + custom optimizations | Fastest |
| 2 | **Lima (VZ + VirtioFS)** | VirtioFS via AVF | Near-native |
| 3 | **Lima (QEMU + 9p)** | 9p protocol | Moderate (slow for node_modules) |
| 4 | **UTM (shared folders)** | SPICE WebDAV or 9p | Moderate |
| 5 | **Lima (SSHFS)** | SSH/SFTP | Slowest |

### Recommendation Summary

**Best overall for your use case (3-6 lightweight Linux dev environments):**

1. **OrbStack** if you are comfortable with commercial software and want the best DX with lowest overhead. The shared VM architecture is ideal for multiple simultaneous environments. The personal use tier is free.

2. **Lima with VZ backend** if you want open source, full control, and are comfortable with CLI-based management. Each VM is fully isolated with its own kernel. More resource-intensive for many instances but maximum flexibility.

3. **Avoid UTM** for this use case -- it is designed for graphical desktop VMs, not headless dev environments.

4. **Avoid Colima** unless your primary need is Docker/containers rather than full Linux environments.

---

## 7. Clipboard and Image Sharing

### How Clipboard Sharing Works

Clipboard sharing between macOS host and Linux VMs is **not provided by Apple Virtualization Framework** natively. Each tool handles it differently:

**OrbStack:**
- Provides bidirectional text clipboard sharing between macOS and Linux machines
- Implemented via OrbStack's custom agent running inside the Linux environment
- Text clipboard works well
- Image clipboard: limited/not supported for direct image paste

**UTM:**
- Uses SPICE guest tools for clipboard sharing
- Requires installing `spice-vdagent` in the Linux guest
- Text clipboard works bidirectionally
- Image clipboard: not reliably supported

**Lima:**
- No built-in clipboard sharing
- Clipboard must be handled manually via SSH or custom scripts
- Workarounds include using `pbcopy`/`pbpaste` via SSH tunneling:
  ```bash
  # In the Lima guest, add to .bashrc:
  alias pbcopy="ssh host.lima.internal pbcopy"
  alias pbpaste="ssh host.lima.internal pbpaste"
  ```
- Some users set up `lemonade` or `clipper` for network-based clipboard sharing

### Pasting Images from macOS Clipboard into Terminal Connected to a Linux VM

This is a challenging use case regardless of the VM tool:

- **Terminal-based image paste**: Standard terminals (Terminal.app, iTerm2, WezTerm, Ghostty, Kitty) do not support pasting images from the clipboard into a running terminal session in a way that a CLI program could receive as image data. The terminal protocol does not natively support this.

- **Workarounds:**
  - Write the clipboard image to a file on the shared filesystem, then reference it from the VM:
    ```bash
    # On macOS:
    osascript -e 'set pngData to the clipboard as <<class PNGf>>' -e 'set filePath to POSIX path of (POSIX file "/tmp/clipboard.png")' -e 'set fileRef to open for access filePath with write permission' -e 'write pngData to fileRef' -e 'close access fileRef'
    # Or use pngpaste:
    pngpaste /tmp/clipboard.png
    # Then access /tmp/clipboard.png from the VM via shared filesystem
    ```
  - Some tools like `kitty` terminal support the Kitty image protocol for displaying images in the terminal, and `wl-clipboard` in the guest can interact with Wayland clipboard, but this does not bridge to macOS clipboard.

- **OrbStack** has the best chance of supporting this in the future given their tight macOS integration, but as of early 2026, direct image clipboard paste from macOS into a Linux VM terminal is not a smooth workflow anywhere.

- **For GUI-based VMs** (UTM with a desktop Linux): If you are running a graphical Linux desktop with SPICE tools, clipboard sharing (including images) can work within the graphical session, but this is not a terminal/CLI workflow.

---

## 8. Shell Experience

### SSH / Shell Connection Quality

When connected to a Linux VM from macOS, the shell experience is generally excellent, nearly indistinguishable from a local shell, provided you use a good terminal emulator and the right connection method.

**Connection Methods (ranked by experience quality):**

1. **OrbStack `orb` command**: Fastest, most seamless. Not SSH-based; uses a direct connection to the Linux environment. Sub-second startup. Full terminal support.

2. **Lima `limactl shell`**: Uses SSH under the hood but with pre-configured keys and config. Very smooth. Sub-second connection once the VM is running.

3. **Direct SSH**: Works with all solutions. Standard SSH experience. Slight connection setup latency (~0.1-0.5 seconds).

4. **UTM serial console / SPICE**: Can be clunky for terminal work, better for graphical desktops.

### zsh with Oh My Zsh

Yes, zsh with Oh My Zsh works perfectly inside Linux VMs. The Linux guest is a full Linux environment, so you can install and configure zsh exactly as you would on any Linux machine:

```bash
# Inside the Linux VM:
sudo apt install zsh   # Ubuntu/Debian
# or
sudo dnf install zsh   # Fedora

# Install Oh My Zsh:
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Change default shell:
chsh -s $(which zsh)
```

**Things that work well:**
- All Oh My Zsh themes (including powerline/nerd font themes, provided your macOS terminal has the right fonts)
- All Oh My Zsh plugins
- zsh-autosuggestions, zsh-syntax-highlighting
- Starship prompt
- fzf, atuin, and other interactive shell tools
- tmux/zellij
- Full 256-color and truecolor support (depends on terminal emulator)
- Unicode/emoji support

**Tips for best experience:**
- Use a modern terminal emulator on macOS (Ghostty, WezTerm, Kitty, iTerm2) for best rendering
- Install Nerd Fonts on the macOS side for proper icon rendering
- Set `TERM=xterm-256color` or appropriate value
- With Lima, the default user has sudo access, making system configuration easy
- With OrbStack, the default user also has sudo access

**Potential issues:**
- If using SSH, ensure your `TERM` variable is forwarded correctly (`SendEnv TERM` in SSH config)
- Some themes that rely on macOS-specific tools (e.g., battery status) will not work, but this is trivially fixable
- Locale settings: ensure `en_US.UTF-8` or your preferred locale is generated in the guest

### Performance of Interactive Shell

The interactive shell experience (keystroke latency, tab completion speed, etc.) is virtually indistinguishable from a local shell when using:
- OrbStack's direct connection
- Lima with VZ backend (SSH over virtio-vsock, very low latency)
- SSH over localhost (Lima, general SSH)

There is no perceptible lag in normal interactive use. Compilation, builds, and other intensive tasks run at near-native speed.

---

## Summary Table

| Feature | Lima (VZ) | OrbStack | UTM | Colima |
|---------|-----------|----------|-----|--------|
| **Backend** | Apple Virtualization Framework | Apple Virtualization Framework | QEMU + HVF | Lima (VZ or QEMU) |
| **VM Isolation** | Full VM per instance | Shared VM, namespace isolation | Full VM per instance | Full VM per instance |
| **Startup Time** | ~3-5s | ~1-2s | ~10-30s | ~5-10s |
| **File Sharing** | VirtioFS (excellent) | VirtioFS (excellent) | 9p/SPICE (moderate) | VirtioFS or 9p |
| **Port Forwarding** | Automatic | Automatic (DNS-based) | Manual | Automatic (Docker) |
| **Clipboard** | Manual/SSH workaround | Built-in (text) | SPICE guest tools | No |
| **VS Code/Cursor** | SSH Remote | SSH Remote | Manual SSH setup | SSH Remote |
| **Multi-instance** | Yes (separate VMs) | Yes (shared VM) | Yes (separate VMs) | Yes (separate VMs) |
| **Resource for 6 instances** | ~6-24 GB RAM | ~2-6 GB RAM | ~8-30 GB RAM | N/A (container-focused) |
| **Rosetta x86_64** | Yes | Yes | No (uses full emulation) | Yes (via Lima) |
| **Cost** | Free/OSS | Free personal / $8/mo commercial | Free/OSS | Free/OSS |
| **Headless-first** | Yes | Yes | No (GUI app) | Yes |
| **Kernel per instance** | Yes (separate) | No (shared) | Yes (separate) | Yes (separate) |
| **Best for** | Full control, OSS, isolation | Best DX, low overhead, integration | GUI desktops, x86 emulation | Docker replacement |

---

## Practical Recommendations for Your Use Case

If you want to run **3-6 simultaneous lightweight Linux dev environments** on Apple Silicon:

### Option A: OrbStack (Best DX, Lowest Overhead)
- Install OrbStack from orbstack.dev
- Create Linux machines: `orb create ubuntu dev1`, `orb create ubuntu dev2`, etc.
- Access them: `orb -m dev1` for shell, or `ssh dev1@orb` for SSH
- File sharing, networking, and clipboard work out of the box
- VS Code: use Remote-SSH with `dev1@orb` as the host
- Total overhead: ~2-4 GB shared across all instances
- Downside: closed source, commercial license for teams, shared kernel

### Option B: Lima with VZ Backend (Best OSS Option, Full Isolation)
- Install via `brew install lima`
- Create instances with VZ backend and VirtioFS:
  ```bash
  limactl create --name=dev1 --vm-type=vz --mount-type=virtiofs template://ubuntu-24.04
  limactl start dev1
  limactl shell dev1
  ```
- Configure SSH for VS Code: `limactl show-ssh --format config dev1 >> ~/.ssh/config`
- Set up clipboard workaround via SSH aliases
- Total overhead: ~2-4 GB per instance
- Downside: more manual setup, no clipboard integration, higher total resource usage for many instances

### Option C: Hybrid
- Use **OrbStack** for your primary dev environments (best DX)
- Use **Lima** for cases where you need full kernel isolation or specific kernel versions
- Use **Colima** if you also need a Docker-compatible environment
