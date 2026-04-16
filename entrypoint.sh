#!/bin/bash
# Entrypoint for claude-dev container.
#
# HAPI is self-hosted: `hapi hub --relay` starts an API+web server and
# exposes it through a public relay tunnel. The token for remote access
# is generated on first run and saved to /root/.hapi/settings.json
# (persisted via the claude-dev-home volume).
#
# `hapi runner start` runs a background service that lets you spawn
# Claude sessions remotely without keeping a terminal open.

set -u

mkdir -p /workspace /root/.hapi

echo "[entrypoint] claude-dev container starting..."
echo "[entrypoint] versions:"
echo "  node:   $(node -v 2>/dev/null || echo missing)"
echo "  claude: $(claude --version 2>/dev/null || echo missing)"
echo "  hapi:   $(hapi --version 2>/dev/null || echo missing)"
echo "  gh:     $(gh --version 2>/dev/null | head -1 || echo missing)"
echo "  git:    $(git --version 2>/dev/null || echo missing)"

# Kick off the runner AFTER the hub is up (hub is started below as PID 1).
# The runner needs the hub's API on :3006 to register.
(
  for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:3006 >/dev/null 2>&1; then
      echo "[entrypoint] hub is up — starting runner"
      hapi runner start 2>&1 | sed 's/^/[runner] /' || \
        echo "[entrypoint] runner start non-zero (may already be running)"
      exit 0
    fi
    sleep 1
  done
  echo "[entrypoint] hub did not come up in 30s — runner not started"
) &

# ------------------------------------------------------------------
# First-time setup reminders
# ------------------------------------------------------------------
if [ ! -f /root/.claude/.credentials.json ] && [ ! -f /root/.config/claude-code/auth.json ]; then
  cat <<'EOF'
[entrypoint] Claude Code is NOT logged in yet.
  First-time setup:
    docker exec -it claude-dev claude
    # follow the device-code flow (Claude Pro/Max)
EOF
fi

if ! gh auth status >/dev/null 2>&1; then
  cat <<'EOF'
[entrypoint] GitHub (gh) is NOT logged in yet.
    docker exec -it claude-dev gh auth login
EOF
fi

# ------------------------------------------------------------------
# Start HAPI hub in foreground (PID 1 via tini).
# - On first run: auto-generates CLI_API_TOKEN -> /root/.hapi/settings.json
# - Listens on 0.0.0.0:3006 — fronted by Coolify/Traefik on HAPI_PUBLIC_URL
# - No --relay: we serve our own HTTPS via the Coolify reverse proxy
#   (so the Telegram Mini App loads from our own domain, not app.hapi.run)
# - Output (token) is visible via `docker logs claude-dev`
# ------------------------------------------------------------------
echo "[entrypoint] starting hapi hub on :${HAPI_LISTEN_PORT:-3006} (foreground)"
echo "[entrypoint] token will print below — grab it from 'docker logs claude-dev'"
exec hapi hub
