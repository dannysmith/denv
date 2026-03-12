# Claude Code Sandboxing: Permission Model, Hooks & Security

> **Context**: Focused research on Claude Code's own security mechanisms — the permission system, hooks, native sandbox, devcontainer support, and auth flows. This is the reference for understanding what Claude Code provides natively and how to configure it inside a container.

## Research Findings (as of early 2026)

---

## 1. Claude Code in Docker / Containers

### Official Devcontainer Support

Anthropic provides an **official reference devcontainer** setup at `github.com/anthropics/claude-code/tree/main/.devcontainer`. It consists of three files:

- **`Dockerfile`** -- builds a container image based on Node.js 20 with essential dev dependencies (git, zsh, fzf, etc.)
- **`devcontainer.json`** -- VS Code devcontainer config with extensions, volume mounts, and settings
- **`init-firewall.sh`** -- iptables-based firewall that restricts outbound network to whitelisted domains only (npm registry, GitHub, Claude API, etc.), with a default-deny policy

**Key features of the official devcontainer:**
- Works with VS Code's Remote - Containers extension
- Custom firewall with precise access control -- only whitelisted outbound domains
- Default-deny network policy
- Firewall rules validated at container startup
- Session persistence (command history survives restarts)
- Cross-platform: macOS, Windows, Linux

**The devcontainer is designed to enable `--dangerously-skip-permissions`** for unattended operation, since the container's network/filesystem isolation provides the safety boundary instead of permission prompts.

**Warning from Anthropic:** Even with devcontainer protections, the setup "doesn't prevent a malicious project from exfiltrating anything accessible in the devcontainer including Claude Code credentials." They recommend only using devcontainers with trusted repositories.

### Docker Installation Gotcha

When installing Claude Code in Docker, installing as root into `/` can cause hangs because the installer scans the entire filesystem. The fix:
```dockerfile
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash
```
Also increase Docker memory limits (`docker build --memory=4g .`).

### MCP Servers Inside Containers

MCP servers can work inside containers, but with caveats:
- Network-based MCP tools (like those hitting external APIs) need the container's firewall rules to allow their domains
- The devcontainer firewall whitelists `*.modelcontextprotocol.io` by default
- Tools like Playwright that need a browser would require a headless browser installed in the container image, plus appropriate network access
- Docker is **incompatible with the sandbox** (the built-in OS-level sandbox) -- you must add `docker` to `excludedCommands` in sandbox settings, or use the `enableWeakerNestedSandbox` mode which "considerably weakens security"

### Auth Flow in Containers

Authentication uses browser-based OAuth by default. In a container:
- If no browser is available, press `c` to copy the login URL to clipboard, then open it in a browser on the host
- For headless/CI environments, use `ANTHROPIC_API_KEY` environment variable instead of OAuth
- The `apiKeyHelper` setting can run a shell script that returns an API key, useful for credential rotation
- Credentials on macOS are stored in the macOS Keychain; in containers (Linux), they use a different storage mechanism

---

## 2. Claude Code Permission Model

### Hierarchical Settings System

Settings apply in precedence order (highest to lowest):
1. **Managed** (highest) -- server-managed, MDM/OS-level policies, or `managed-settings.json`
2. **Command line arguments** -- temporary session overrides
3. **Local** -- `.claude/settings.local.json` (project-specific, gitignored)
4. **Project** -- `.claude/settings.json` (team-shared, in git)
5. **User** (lowest) -- `~/.claude/settings.json` (personal)

Array settings **merge** across scopes rather than replace.

### Permission Rules

Rules follow the format `Tool` or `Tool(specifier)` and are evaluated: **deny first, then ask, then allow**. First matching rule wins.

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run lint)",
      "Bash(npm run test *)",
      "Bash(git diff *)",
      "Read(./src/**)"
    ],
    "ask": [
      "Bash(git push *)"
    ],
    "deny": [
      "Bash(curl *)",
      "Bash(rm -rf *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ]
  }
}
```

### Wildcard Patterns (NOT Regex)

Permission rules use **glob patterns**, not regex:
- `*` matches any sequence of characters except `/`
- `**` matches any sequence including `/` (recursive)
- `Bash(npm run *)` matches `npm run test`, `npm run lint`, etc.
- `Read(./secrets/**)` matches all files in `secrets/` recursively
- A space before `*` matters: `Bash(ls *)` matches `ls -la` but NOT `lsof`, while `Bash(ls*)` matches both

### Tool-Specific Patterns

| Tool | Pattern Examples |
|------|-----------------|
| **Bash** | `Bash(git diff *)`, `Bash(npm run test *)`, `Bash(docker build *)` |
| **Read** | `Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)`, `Read(~/.aws/credentials)` |
| **Edit** | `Edit(./src/**)`, `Edit(./README.md)` |
| **WebFetch** | `WebFetch(domain:github.com)`, `WebFetch(domain:*.npmjs.org)` |
| **MCP** | `mcp__puppeteer`, `mcp__github__search_repositories` |
| **Agent** | `Agent(Explore)`, `Agent(Plan)` |

### Important Limitation: Bash Patterns Are Fragile

Anthropic explicitly warns that Bash permission patterns "that try to constrain command arguments are fragile." For example, `Bash(curl http://github.com/ *)` won't match:
- Options before URL: `curl -X GET http://github.com/...`
- Different protocol: `curl https://github.com/...`
- Redirects: `curl -L http://bit.ly/xyz`
- Variables: `URL=http://github.com && curl $URL`
- Extra spaces

**Claude Code IS aware of shell operators** though -- a prefix rule like `Bash(safe-cmd *)` won't give permission to run `safe-cmd && other-cmd`.

### Answering: Can You Do `gh api GET` but Block `gh api POST`?

With **permission rules alone**: No, not reliably. The pattern `Bash(gh api *)` would match both GET and POST. You can't distinguish HTTP methods via glob patterns in settings.json.

**With hooks**: Yes. A `PreToolUse` hook can parse the full command, inspect arguments, and make the allow/deny decision programmatically. This is the correct approach for this use case (see Section 3).

### Permission Modes

| Mode | Description |
|------|-------------|
| `default` | Standard: prompts for permission on first use |
| `acceptEdits` | Auto-accepts file edits, still prompts for commands |
| `plan` | Read-only: Claude can analyze but not modify or execute |
| `dontAsk` | Auto-denies tools unless pre-approved |
| `bypassPermissions` | Skips ALL permission prompts (containers/VMs only) |

### Managed Settings (Enterprise)

For organization-wide enforcement:
- `disableBypassPermissionsMode: "disable"` -- prevents `--dangerously-skip-permissions`
- `allowManagedPermissionRulesOnly: true` -- prevents user/project permission rules
- `allowManagedHooksOnly: true` -- prevents user/project hooks
- `allowManagedMcpServersOnly: true` -- limits MCP servers to admin-approved list

Managed settings locations:
- **macOS:** `/Library/Application Support/ClaudeCode/managed-settings.json`
- **Linux/WSL:** `/etc/claude-code/managed-settings.json`
- **Windows:** `C:\Program Files\ClaudeCode\managed-settings.json`

---

## 3. Claude Code Hooks for Security Gating

### What Are Hooks?

Hooks are user-defined shell commands, HTTP endpoints, or LLM prompts that execute at specific lifecycle points. They provide **deterministic** control (as opposed to relying on the LLM to make good decisions).

### Hook Types

1. **Command hooks** (`type: "command"`) -- run a shell command, receive JSON on stdin
2. **HTTP hooks** (`type: "http"`) -- POST event data to a URL endpoint
3. **Prompt hooks** (`type: "prompt"`) -- single-turn LLM evaluation (yes/no decision)
4. **Agent hooks** (`type: "agent"`) -- multi-turn subagent with tool access for verification

### Key Hook Events for Security Gating

| Event | When | Can Block? |
|-------|------|-----------|
| `PreToolUse` | Before a tool call executes | YES -- exit 2 or return `permissionDecision: "deny"` |
| `PostToolUse` | After a tool call succeeds | Can block via `decision: "block"` |
| `UserPromptSubmit` | When user submits a prompt | YES -- exit 2 rejects the prompt |
| `ConfigChange` | When settings change mid-session | YES -- exit 2 blocks the change |
| `PermissionRequest` | When a permission dialog appears | Can override with `allow`/`deny`/`ask` |

### Example: Blocking Destructive Commands (Official Example)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/block-rm.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/bin/bash
# .claude/hooks/block-rm.sh
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'rm -rf'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Destructive command blocked by hook"
    }
  }'
else
  exit 0
fi
```

### Example: Gating `gh api` Read vs Write

To allow `gh api GET` but block `gh api POST/PUT/DELETE/PATCH`:

```bash
#!/bin/bash
# .claude/hooks/gate-gh-api.sh
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Check if this is a gh api command
if echo "$COMMAND" | grep -qE '^\s*gh\s+api\s'; then
  # Block if it contains write methods
  if echo "$COMMAND" | grep -qiE '\-X\s*(POST|PUT|DELETE|PATCH)|--method\s*(POST|PUT|DELETE|PATCH)'; then
    echo "Blocked: gh api write operations not allowed" >&2
    exit 2
  fi
fi

exit 0
```

### Example: Comprehensive Read vs Write Gating

A more comprehensive hook could classify commands as read vs write operations:

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Define write-operation patterns
WRITE_PATTERNS=(
  "rm "
  "mv "
  "cp "
  "chmod "
  "chown "
  "git push"
  "git reset"
  "docker rm"
  "docker stop"
  "kubectl delete"
  "kubectl apply"
  "terraform apply"
  "terraform destroy"
)

for pattern in "${WRITE_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -q "$pattern"; then
    jq -n --arg reason "Write operation blocked: contains '$pattern'" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
  fi
done

exit 0
```

### Anthropic's Official Bash Command Validator Example

Anthropic provides a reference implementation at `github.com/anthropics/claude-code/blob/main/examples/hooks/bash_command_validator_example.py` -- a Python script that validates bash commands before execution. This serves as the canonical example of using hooks for security gating.

### Matcher Patterns for Hooks (These ARE Regex)

Unlike permission rules (which use globs), hook matchers use **regex patterns**:
- `Bash` -- match only Bash tool calls
- `Edit|Write` -- match Edit or Write tool calls
- `mcp__github__.*` -- match all GitHub MCP tools
- `mcp__.*__write.*` -- match any MCP tool containing "write"

### Hook Limitations

- Command hooks communicate through stdout/stderr/exit codes only
- Default timeout is 10 minutes (configurable per hook)
- `PostToolUse` hooks cannot undo already-executed actions
- `PermissionRequest` hooks do NOT fire in headless mode (`-p`); use `PreToolUse` instead
- Hooks edited in settings files mid-session require review in `/hooks` menu before taking effect (security measure)

---

## 4. Native Sandboxing (OS-Level)

### How It Works

Claude Code has a **built-in sandbox** using OS-level primitives:
- **macOS:** Uses Seatbelt for enforcement
- **Linux:** Uses bubblewrap (`bwrap`) for isolation
- **WSL2:** Uses bubblewrap (same as Linux)
- **WSL1:** Not supported

The sandbox provides:
- **Filesystem isolation:** Restrict writes to the current working directory; configurable allowed/denied paths
- **Network isolation:** Domain-based restrictions via a proxy server running outside the sandbox
- All child processes inherit sandbox restrictions

### Enabling Sandboxing

Run `/sandbox` in Claude Code to enable. Two modes:
1. **Auto-allow mode:** Sandboxed bash commands run without permission prompts
2. **Regular permissions mode:** All commands still go through standard permission flow

### Sandbox Configuration

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "excludedCommands": ["git", "docker"],
    "allowUnsandboxedCommands": true,
    "filesystem": {
      "allowWrite": ["//tmp/build", "~/.kube"],
      "denyWrite": ["//etc", "//usr/local/bin"],
      "denyRead": ["~/.aws/credentials"]
    },
    "network": {
      "allowedDomains": ["github.com", "*.npmjs.org"],
      "allowUnixSockets": ["~/.ssh/agent-socket"],
      "allowLocalBinding": false
    }
  }
}
```

### Important: Sandbox Applies Only to Bash

The sandbox restricts only the **Bash tool** and its child processes. It does NOT sandbox:
- Claude Code's built-in Read/Write/Edit tools
- WebSearch/WebFetch tools
- MCP tool calls
- Hooks themselves

For those, you must use permission rules and/or hooks.

### Open Source Sandbox Runtime

Anthropic has open-sourced the sandbox runtime as an npm package: `@anthropic-ai/sandbox-runtime`. You can use it to sandbox arbitrary programs, including MCP servers:
```bash
npx @anthropic-ai/sandbox-runtime <command-to-sandbox>
```

### Security Limitations of the Sandbox

- Network filtering operates at domain level; it does not inspect traffic content
- Broad domains like `github.com` could theoretically be used for data exfiltration
- Domain fronting attacks are possible in some cases
- `allowUnixSockets` for things like Docker socket effectively grants host system access
- Linux's `enableWeakerNestedSandbox` (for use inside Docker) "considerably weakens security"
- Overly broad filesystem write permissions can enable privilege escalation

---

## 5. Claude Code on the Web (Cloud VMs)

Anthropic runs Claude Code in **isolated VMs** for web sessions:
- Each session gets its own Anthropic-managed VM
- Network access limited by default to an extensive allowlist (package registries, cloud providers, GitHub, etc.)
- Git credentials never enter the sandbox -- handled by a secure proxy with scoped credentials
- Git push restricted to current working branch only
- All operations logged for audit
- Environments auto-terminated after session completion

This is essentially Anthropic's own "ring-fenced" approach, but it's only available through claude.ai/code, not for self-hosted setups.

---

## 6. Claude Code in Remote / SSH Environments

### Remote Control

Claude Code offers "Remote Control" -- a feature where your local Claude Code session can be controlled from a browser or mobile app:
- The session runs locally on your machine
- The web/mobile interface is just a view into the local session
- All MCP servers, tools, and project config stay available
- Outbound HTTPS only; no inbound ports opened
- Auto-reconnects after network drops
- One remote session per Claude Code instance

### SSH Usage

Claude Code works over SSH, but with some friction:
- The OAuth login flow opens a browser -- in SSH, this means the browser opens on the wrong machine. You need to copy the URL manually and open it in your local browser.
- Use `ANTHROPIC_API_KEY` environment variable to skip browser-based auth entirely
- Latency depends on your SSH connection quality
- Terminal rendering (including the fancy TUI) works over SSH
- Image paste from clipboard does NOT work in remote/SSH sessions (see Section 7)

### Headless / CI Mode

For automated/scripted use:
```bash
claude -p "Fix the bug in auth.py" --allowedTools "Read,Edit,Bash"
```
- `-p` flag runs non-interactively
- `--allowedTools` auto-approves specified tools
- Supports JSON output, structured schemas, streaming
- `PermissionRequest` hooks do NOT fire in `-p` mode; use `PreToolUse` hooks instead

---

## 7. Image Paste / Clipboard

### How Image Input Works

- **Interactive mode:** `Ctrl+V` / `Cmd+V` / `Alt+V` (Windows) pastes an image from clipboard
- Claude Code is multimodal -- it can process pasted images (screenshots, diagrams, etc.)
- Images can also be referenced via file path using `@path/to/image.png`
- The Read tool can view image files (PNG, JPG, etc.) when given a file path

### In Remote / Container Environments

- **Clipboard paste does NOT work** in SSH sessions or containers without a display server
- **File paths DO work** -- you can reference images by path: `@/path/to/screenshot.png`
- **Remote Control** sessions from a browser/mobile app should support image input through the web interface
- **Claude Code on the web** supports image input through the browser interface

---

## 8. Community Approaches & Patterns

### The Autonomy vs. Safety Problem

The core tension: Claude Code is most productive when given broad permissions (`--dangerously-skip-permissions` or `bypassPermissions` mode), but this creates real risk of destructive actions, data exfiltration, or credential exposure.

### Emerging Patterns from the Community

Based on the official documentation, example configurations, and guidance:

#### Pattern 1: Devcontainer + Skip Permissions

**The Anthropic-recommended approach for maximum autonomy:**
1. Use the official devcontainer setup
2. Firewall restricts network to whitelisted domains
3. Filesystem is isolated from host
4. Run with `--dangerously-skip-permissions`
5. Only use with trusted repositories

**Pros:** Maximum productivity, no permission fatigue
**Cons:** Credentials still accessible within container; malicious project code could exfiltrate

#### Pattern 2: Sandbox + Auto-Allow

**For local development with moderate safety:**
1. Enable sandbox via `/sandbox` in auto-allow mode
2. Configure allowed filesystem write paths
3. Configure allowed network domains
4. Sandboxed commands auto-approved; unsandboxable ones go through permission flow

**Pros:** Works locally, no container overhead, OS-level enforcement
**Cons:** Only covers Bash tool, not file edits or MCP; domain-level network filtering only

#### Pattern 3: Hooks-Based Policy Engine

**For fine-grained, custom security:**
1. Define `PreToolUse` hooks that inspect every tool call
2. Script decides allow/deny based on command analysis
3. Can classify read vs. write operations
4. Can gate specific tools (e.g., allow `gh api GET` but block `POST`)

**Pros:** Extremely granular, can implement any policy
**Cons:** Requires writing/maintaining scripts; command classification is inherently fragile; shell commands have too many ways to achieve the same thing

#### Pattern 4: Layered Defense (Recommended)

The most robust approach combines multiple layers:

```
Layer 1: Permission rules (deny dangerous tools/files)
Layer 2: Sandbox (OS-level filesystem + network isolation)
Layer 3: Hooks (programmatic validation of tool calls)
Layer 4: Container/VM (full environment isolation)
```

Anthropic's official example settings demonstrate this with three tiers:
- **`settings-lax.json`**: Disables `--dangerously-skip-permissions`, blocks plugin marketplaces
- **`settings-strict.json`**: Above + blocks user-defined permissions/hooks, denies web tools, requires approval for all Bash
- **`settings-bash-sandbox.json`**: Blocks user-defined permissions, forces all Bash into sandbox

#### Pattern 5: Plan Mode + Remote Execution

1. Run Claude Code locally in Plan Mode (`--permission-mode plan`) -- read-only, no modifications
2. Collaborate on the approach
3. Send execution to Claude Code on the web (`--remote`) for sandboxed cloud execution

**Pros:** Local exploration is safe; actual execution happens in Anthropic's isolated VMs
**Cons:** Requires web access; slower iteration cycle

---

## 9. Official Anthropic Guidance Summary

### Explicit Recommendations from Anthropic's Docs

1. **"Use virtual machines (VMs) to run scripts and make tool calls, especially when interacting with external web services"** -- listed under best practices for working with untrusted content

2. **"Consider using devcontainers for additional isolation"** -- listed under security best practices for sensitive code

3. **"Start restrictive: Begin with minimal permissions and expand as needed"** -- sandbox best practices

4. **"Combine with permissions: Use sandboxing alongside IAM policies for comprehensive security"** -- defense in depth

5. **"Review all suggested changes before approval"** -- the user is the final safety layer

6. **The official devcontainer is positioned as THE solution** for teams that need to run `--dangerously-skip-permissions` safely

7. **Managed settings** are the enterprise answer -- organizations can enforce permissions, hook policies, MCP server lists, and disable bypass mode via MDM/OS-level policy files

### What's NOT Available (Yet)

- **No official Docker image** for running Claude Code as a service
- **No built-in command classification** (read vs. write) -- you must build this yourself via hooks
- **No built-in network-level monitoring** beyond the sandbox proxy
- **No way to restrict the Edit/Write tools at the sandbox level** -- only permission rules and hooks apply to file modifications
- **The sandbox does not cover MCP tools** -- MCP security relies entirely on permission rules and hooks

---

## 10. Practical Setup Recommendations

### For a Ring-Fenced Local Environment

```json
// ~/.claude/settings.json or .claude/settings.json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(npm run test *)",
      "Bash(npm run lint *)",
      "Read(./src/**)"
    ],
    "deny": [
      "Bash(curl *)",
      "Bash(wget *)",
      "Bash(rm -rf *)",
      "Bash(git push *)",
      "Bash(git reset --hard *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Read(~/.aws/**)",
      "Read(~/.ssh/**)",
      "WebFetch"
    ],
    "defaultMode": "acceptEdits",
    "disableBypassPermissionsMode": "disable"
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["docker"],
    "filesystem": {
      "denyWrite": ["//etc", "//usr/local"],
      "denyRead": ["~/.aws/credentials", "~/.ssh/id_*"]
    },
    "network": {
      "allowedDomains": ["github.com", "*.npmjs.org", "api.anthropic.com"]
    }
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/validate-command.sh"
          }
        ]
      }
    ]
  }
}
```

### For Maximum Isolation (Devcontainer)

1. Clone the reference devcontainer from `github.com/anthropics/claude-code/tree/main/.devcontainer`
2. Customize `init-firewall.sh` to whitelist only the domains you need
3. Set `ANTHROPIC_API_KEY` as an environment variable (avoid OAuth in containers)
4. Run with `claude --dangerously-skip-permissions`
5. Mount your project directory as a volume
6. Do NOT mount `~/.ssh`, `~/.aws`, or other credential directories

---

## Sources

All information sourced from official Anthropic documentation at `code.claude.com/docs/en/`:
- `/overview` -- Claude Code overview
- `/settings` -- Settings and configuration reference
- `/hooks` and `/hooks-guide` -- Hooks reference and guide
- `/security` -- Security documentation
- `/permissions` -- Permission configuration
- `/sandboxing` -- Sandbox documentation
- `/devcontainer` -- Development container setup
- `/claude-code-on-the-web` -- Cloud execution
- `/remote-control` -- Remote control feature
- `/headless` (now `/en/headless` -> Agent SDK) -- Programmatic/headless usage
- `/authentication` -- Auth and credential management
- `/interactive-mode` -- Interactive features including image paste
- `/troubleshooting` -- Known issues including Docker installation
- `github.com/anthropics/claude-code/tree/main/examples/settings` -- Example settings configurations
