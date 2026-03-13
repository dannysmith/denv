#!/usr/bin/env bash
# PreToolUse hook for Bash commands.
# Gates write operations to external services — requires user confirmation.
# Receives tool call JSON on stdin. Returns JSON with permissionDecision if gated.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // ""')

# No command to check
[[ -z "$cmd" ]] && exit 0

gate() {
    jq -n --arg reason "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

# --- git push (any form) ---
if echo "$cmd" | grep -qE '\bgit\s+push\b'; then
    gate "git push — writes to remote repository"
fi

# --- gh pr create/merge/close/edit ---
if echo "$cmd" | grep -qE '\bgh\s+pr\s+(create|merge|close|edit)\b'; then
    gate "gh pr write operation — modifies GitHub PRs"
fi

# --- gh issue create/close/edit ---
if echo "$cmd" | grep -qE '\bgh\s+issue\s+(create|close|edit)\b'; then
    gate "gh issue write operation — modifies GitHub issues"
fi

# --- gh release create ---
if echo "$cmd" | grep -qE '\bgh\s+release\s+create\b'; then
    gate "gh release create — publishes a GitHub release"
fi

# --- gh api with mutating HTTP methods ---
if echo "$cmd" | grep -qE '\bgh\s+api\b' && \
   echo "$cmd" | grep -qE '(-X|--method)\s*(POST|PUT|DELETE|PATCH)'; then
    gate "gh api with mutating method — writes to GitHub API"
fi

# --- npm/yarn publish ---
if echo "$cmd" | grep -qE '\b(npm|yarn|pnpm|bun)\s+publish\b'; then
    gate "package publish — publishes to npm registry"
fi

# --- cargo publish ---
if echo "$cmd" | grep -qE '\bcargo\s+publish\b'; then
    gate "cargo publish — publishes to crates.io"
fi

# All other commands — allow (no output, exit 0)
exit 0
