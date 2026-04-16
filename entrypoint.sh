#!/bin/bash
# Entrypoint for claude-dev container.
# - On first run: user must exec in and auth hapi/claude/gh.
# - On subsequent runs: auto-starts hapi runner (phone/web access).

set -u

mkdir -p /workspace /root/.config/hapi /root/.claude

echo "[entrypoint] claude-dev container starting..."
echo "[entrypoint] versions:"
echo "  node:   $(node -v 2>/dev/null || echo missing)"
echo "  claude: $(claude --version 2>/dev/null || echo missing)"
echo "  hapi:   $(hapi --version 2>/dev/null || echo missing)"
echo "  gh:     $(gh --version 2>/dev/null | head -1 || echo missing)"
echo "  git:    $(git --version 2>/dev/null || echo missing)"

# Try starting hapi runner if already authed. Harmless if already running.
if hapi auth status >/dev/null 2>&1; then
  echo "[entrypoint] HAPI is authenticated — starting runner"
  hapi runner start || echo "[entrypoint] runner start returned non-zero (may already be running)"
else
  cat <<'EOF'
[entrypoint] HAPI is NOT authenticated yet.

First-time setup — exec into the container and run:

  docker exec -it claude-dev bash
  hapi auth login        # opens a URL — log in on phone/laptop
  claude                 # triggers Claude Code login (subscription device-code)
  gh auth login          # GitHub auth for pushing

Then restart the container to auto-start the runner:
  docker restart claude-dev

EOF
fi

# Keep PID 1 alive; tini forwards signals for clean shutdown.
echo "[entrypoint] container ready — sleeping"
exec tail -f /dev/null
