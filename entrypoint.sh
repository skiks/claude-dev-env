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

# ------------------------------------------------------------------
# Weekly auto-rebuild: every Sunday at 04:17 triggers a Coolify
# redeploy with no-cache so claude-code and hapi stay on @latest.
# COOLIFY_URL and COOLIFY_TOKEN must be set in the container env.
# ------------------------------------------------------------------
if [ -n "${COOLIFY_URL:-}" ] && [ -n "${COOLIFY_TOKEN:-}" ]; then
  echo "[entrypoint] setting up weekly rebuild cron"
  echo "COOLIFY_URL=${COOLIFY_URL}" > /etc/cron.d/weekly-rebuild-env
  echo "COOLIFY_TOKEN=${COOLIFY_TOKEN}" >> /etc/cron.d/weekly-rebuild-env
  cat > /etc/cron.d/weekly-rebuild << EOF
SHELL=/bin/bash
17 4 * * 0 root . /etc/cron.d/weekly-rebuild-env && curl -sf "${COOLIFY_URL}/api/v1/deploy?uuid=s8gs80kgs0g8c84k48sssosc&force=true&no_cache=true" -H "Authorization: Bearer ${COOLIFY_TOKEN}" >> /var/log/weekly-rebuild.log 2>&1
EOF
  chmod 0644 /etc/cron.d/weekly-rebuild
  chmod 0600 /etc/cron.d/weekly-rebuild-env
  cron
  echo "[entrypoint] cron started (weekly rebuild every Sunday 04:17)"
else
  echo "[entrypoint] COOLIFY_URL/TOKEN not set — weekly rebuild cron skipped"
fi

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
# Start RUBRIC dashboard in the same container on :5050.
# ------------------------------------------------------------------
(
  sleep 2
  RUBRIC_DIR=/workspace/rubric
  SCAFFOLD=$RUBRIC_DIR/templates/scaffold
  if [ ! -d "$RUBRIC_DIR/.git" ]; then
    if TOKEN=$(gh auth token 2>/dev/null); then
      echo "[entrypoint] cloning skiks/rubric into $RUBRIC_DIR"
      git clone -q "https://oauth2:${TOKEN}@github.com/skiks/rubric.git" "$RUBRIC_DIR" 2>&1 | sed 's/^/[rubric-clone] /' || \
        echo "[entrypoint] rubric clone failed — continuing without"
    else
      echo "[entrypoint] gh not authenticated; skipping rubric clone"
    fi
  else
    (cd "$RUBRIC_DIR" && git pull -q 2>&1 | sed 's/^/[rubric-pull] /') || \
      echo "[entrypoint] rubric pull skipped"
  fi
  if [ -f "$SCAFFOLD/server.js" ]; then
    sed -i 's/127\.0\.0\.1/0.0.0.0/' "$SCAFFOLD/server.js"
    echo "[entrypoint] starting rubric on :5050"
    (cd "$SCAFFOLD" && PORT=5050 SKILL_TREE_ROOT=/workspace node server.js 2>&1 | sed 's/^/[rubric] /') &
  else
    echo "[entrypoint] rubric scaffold not found at $SCAFFOLD — skipping"
  fi
) &

# ------------------------------------------------------------------
# First-time setup reminders
# ------------------------------------------------------------------
if [ ! -f /root/.claude/.credentials.json ] && [ ! -f /root/.config/claude-code/auth.json ]; then
  cat <<'SETUPEOF'
[entrypoint] Claude Code is NOT logged in yet.
  First-time setup:
    docker exec -it claude-dev claude
    # follow the device-code flow (Claude Pro/Max)
SETUPEOF
fi

if ! gh auth status >/dev/null 2>&1; then
  cat <<'SETUPEOF'
[entrypoint] GitHub (gh) is NOT logged in yet.
    docker exec -it claude-dev gh auth login
SETUPEOF
fi

# ------------------------------------------------------------------
# Start HAPI hub in foreground (PID 1 via tini).
# ------------------------------------------------------------------
echo "[entrypoint] starting hapi hub on :${HAPI_LISTEN_PORT:-3006} (foreground)"
echo "[entrypoint] token will print below — grab it from 'docker logs claude-dev'"
exec hapi hub
