# claude-dev-env

Isolated Docker container running **Claude Code** + self-hosted **HAPI hub** for remote AI-assisted development on a Coolify VM. Controlled from phone/desktop via a public HAPI relay URL — no need for the local machine to be powered on.

## Architecture

```
phone / laptop  ─── public relay URL (HAPI's tunnel)
                                  │
                                  v
         claude-dev container (on your VM)
           ├─ hapi hub --relay     (self-hosted API + web UI)
           ├─ hapi runner          (spawns Claude sessions in background)
           ├─ Claude Code CLI      (Anthropic subscription / Pro·Max)
           └─ /workspace           (git clones of your projects)
                                  │
                                  v  git push
                              GitHub
                                  │
                                  v  webhook
                    Coolify redeploys prod containers
```

Claude never touches production containers directly. It edits source in `/workspace`, pushes to GitHub, and Coolify handles deploys.

## Isolation guarantees

- **No Docker socket mounted** — cannot manage other containers.
- **No host filesystem mounted** — cannot reach host files.
- **No inbound ports exposed** — HAPI dials out to the relay (WireGuard+TLS). Firewall untouched.
- **Root inside container** ≠ root on host (standard Docker isolation).

## Deploy via Coolify

1. Push this repo to GitHub (private is fine — Coolify supports private via its GitHub App integration).
2. In Coolify: **New Resource → Docker Compose → Public Repository** (or Private).
3. Repo URL: `https://github.com/skiks/claude-dev-env`, branch `main`, compose path `docker-compose.yml`.
4. Deploy.

## First-time setup

After first deploy, fetch the generated HAPI token + relay URL and log in to Claude/GitHub:

```bash
# 1. Grab the auto-generated HAPI token + public relay URL from logs
docker logs claude-dev | grep -E "CLI_API_TOKEN|relay|Public URL|Token:" -A 2

# 2. Log in to Claude (subscription device-code)
docker exec -it claude-dev claude
#   follow prompts, pick "Claude Pro/Max subscription", auth in browser on phone

# 3. Log in to GitHub
docker exec -it claude-dev gh auth login
#   HTTPS, Login via browser, scopes: repo,workflow

# 4. Clone a project into /workspace to work on
docker exec -it claude-dev bash -c "cd /workspace && gh repo clone <your-org>/<your-repo>"

# 5. Open the relay URL on your phone/laptop, paste the token when prompted
```

## Daily use

- Open the relay URL (printed in container logs on first run).
- Paste the CLI_API_TOKEN.
- Spawn a Claude session from the web UI pointed at `/workspace/<project>`.
- Or `hapi` from any other machine configured with the same token.

## Upgrade Claude Code / HAPI

```bash
docker exec claude-dev npm update -g @anthropic-ai/claude-code @twsxtd/hapi
docker restart claude-dev
```

For a full image rebuild, use Coolify's "Redeploy → Force rebuild".

## Volumes (persisted across restarts and redeploys)

- `claude-dev-workspace` → `/workspace` (your git clones, edits)
- `claude-dev-home` → `/root` (auth tokens: hapi, claude, gh; shell history; git config)

Backup workspace:
```bash
docker run --rm -v claude-dev-workspace:/src -v $PWD:/dst alpine \
  tar czf /dst/workspace-backup.tgz -C /src .
```
