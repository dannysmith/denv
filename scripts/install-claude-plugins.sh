#!/usr/bin/env bash
# Install/update the standard denv Claude Code plugin set.
# Requires: claude auth login to have been completed.
# Idempotent — safe to re-run.

set -euo pipefail

# Check auth
if ! claude auth status &>/dev/null; then
    echo "denv: Claude auth required. Run 'claude auth login' first." >&2
    exit 1
fi

# Add custom marketplaces (idempotent)
echo "Adding marketplaces..."
claude plugin marketplace add dannysmith/claude-marketplace 2>/dev/null || true
claude plugin marketplace add microsoft/playwright-cli 2>/dev/null || true
# claude-plugins-official is built-in

# Install or update plugins
PLUGINS=(
    "css-expert@dannysmith"
    "frontend-design@claude-plugins-official"
    "playwright-cli@playwright-cli"
)

for plugin in "${PLUGINS[@]}"; do
    echo "Installing/updating $plugin..."
    claude plugin install "$plugin" 2>/dev/null || claude plugin update "$plugin" 2>/dev/null || true
done

echo "Done. Claude plugins installed."
