FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base system packages
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
    && rm -rf /var/lib/apt/lists/*

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

# Install Claude Code as dev user (must not install from / — installer scans filesystem and hangs)
USER dev
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
ENV PATH="/home/dev/.local/bin:${PATH}"

# Install Python via uv to a shared location (not /home/dev, which is a named volume)
ENV UV_PYTHON_INSTALL_DIR=/opt/python
RUN uv python install \
    && PYDIR=$(ls -1d /opt/python/cpython-3.*.* | head -1) \
    && ln -s "$PYDIR/bin/python3" /usr/local/bin/python3 \
    && ln -s "$PYDIR/bin/python3" /usr/local/bin/python

# Copy entrypoint
COPY scripts/entrypoint.sh /opt/denv/entrypoint.sh
RUN chmod +x /opt/denv/entrypoint.sh

USER dev
WORKDIR /workspace

ENTRYPOINT ["/opt/denv/entrypoint.sh"]
CMD ["zsh"]
