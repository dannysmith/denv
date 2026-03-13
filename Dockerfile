FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base system packages + CLI tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    zsh \
    sudo \
    ca-certificates \
    jq \
    build-essential \
    unzip \
    openssh-client \
    locales \
    ripgrep \
    fd-find \
    bat \
    tree \
    ncdu \
    sqlite3 \
    libvips-tools \
    miller \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/batcat /usr/local/bin/bat

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js (latest LTS via fnm)
ENV FNM_DIR=/opt/fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /opt/fnm \
    && /opt/fnm/fnm install --lts \
    && /opt/fnm/fnm default lts-latest
ENV PATH="/opt/fnm/aliases/default/bin:${PATH}"

# Install Bun
ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/opt/bun/bin:${PATH}"

# Install GitHub CLI (official method from https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager — replaces pip, venv, pyenv, pipx)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Create non-root user 'dev' with UID 501 (matches macOS default) and zsh
RUN groupadd -g 501 dev \
    && useradd -m -u 501 -g 501 -s /bin/zsh dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Claude Code as dev user
USER dev
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Python via uv
RUN uv python install \
    && ln -s $(find ~/.local/bin -name 'python3.*' -not -name '*-*' | head -1) ~/.local/bin/python3 \
    && ln -s ~/.local/bin/python3 ~/.local/bin/python

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/dev/.cargo/bin:${PATH}"

# Install Go (official tarball from go.dev)
USER root
RUN ARCH=$(dpkg --print-architecture) \
    && wget -nv -O /tmp/go.tar.gz "https://go.dev/dl/$(wget -qO- 'https://go.dev/VERSION?m=text' | head -1).linux-${ARCH}.tar.gz" \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm -f /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/dev/go"
ENV PATH="/home/dev/go/bin:${PATH}"

# Install CLI tools via go install (as dev user)
USER dev
RUN go install github.com/mikefarah/yq/v4@latest

# Install Python CLI tools via uv
RUN uv tool install showboat \
    && uv tool install chartroom

# Install Playwright CLI + Chromium
# Browsers go to /opt so they're accessible to the dev user (not trapped in /root)
# Use the playwright version bundled with @playwright/cli to avoid revision mismatch
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
ENV PLAYWRIGHT_MCP_BROWSER=chromium
RUN bun install -g @playwright/cli \
    && PW_VERSION=$(node -e "console.log(require('/opt/bun/install/global/node_modules/playwright/package.json').version)") \
    && npx playwright@$PW_VERSION install --with-deps chromium \
    && chmod -R o+rx /opt/playwright-browsers

# Install rodney (headless Chrome automation CLI, needs Chrome from Playwright)
USER dev
RUN go install github.com/simonw/rodney@latest

# --- Terminal & Dotfiles ---
USER root

# Install ghostty terminfo (non-fatal if unavailable)
RUN (curl -fsSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/terminfo/ghostty.terminfo -o /tmp/ghostty.terminfo \
    && tic -x -o /usr/share/terminfo /tmp/ghostty.terminfo \
    && rm -f /tmp/ghostty.terminfo) \
    || echo "Warning: ghostty terminfo not installed"

# Copy denv scripts and hooks
COPY scripts/entrypoint.sh /opt/denv/entrypoint.sh
COPY scripts/install-claude-plugins.sh /opt/denv/install-claude-plugins.sh
COPY claude/hooks/gate-writes.sh /opt/denv/hooks/gate-writes.sh
RUN chmod +x /opt/denv/entrypoint.sh /opt/denv/install-claude-plugins.sh /opt/denv/hooks/gate-writes.sh

# Copy dotfiles
COPY --chown=dev:dev dotfiles/zshrc /home/dev/.zshrc
COPY --chown=dev:dev dotfiles/gitconfig /home/dev/.gitconfig
COPY --chown=dev:dev dotfiles/gitignore_global /home/dev/.gitignore_global

# Copy Claude Code config
COPY --chown=dev:dev claude/CLAUDE.md /home/dev/.claude/CLAUDE.md
COPY --chown=dev:dev claude/settings.json /home/dev/.claude/settings.json
COPY --chown=dev:dev claude/.claude.json /home/dev/.claude.json

ENV COLORTERM=truecolor

USER dev
ENV PATH="/home/dev/.local/bin:${PATH}"
WORKDIR /workspace

ENTRYPOINT ["/opt/denv/entrypoint.sh"]
CMD ["zsh"]
