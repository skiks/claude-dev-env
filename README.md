# claude-dev-env

Isolated Docker container running **Claude Code** + **HAPI** for remote AI-assisted development on a Coolify VM. Designed to be controlled from a phone/desktop via [app.hapi.run](https://app.hapi.run) without needing a local machine powered on.

## Architecture

```
phone / laptop
     |
     v
hapi.run  (relay — WireGuard + TLS)
     |
     v
claude-dev container on your VM
  - Claude Code CLI (Anthropic subscription)
  - HAPI runner
  - git, gh, node, ripgrep, tmux, ...
  - /workspace  <- git clones of your projects
     |
     v (git push)
GitHub
     |
     v (webhook)
Coolify auto-redeploys your production containers
```

Claude never touches production containers directly. It edits source in `/workspace`, pushes to GitHub, and Coolify handles deploys.

## Isolation guarantees

- **No Docker socket** mounted — container cannot manage other containers.
- **No host filesystem** mounted — container sees only its own volumes.
- **No inbound ports** — HAPI dials out to relay, no firewall changes needed.
- **Root inside container** ≠ root on host (standard Docker isolation).

## Deploy via Coolify

1. Push this repo to GitHub (private is fine).
2. In Coolify: **New Resource → Docker Compose → Public Repository** (or Private with GitHub App).
3. Paste repo URL, branch `main`, build context `/`, compose path `docker-compose.yml`.
4. Deploy.

## First-time setup (after first deploy)

SSH to the VM, then:

```bash
docker exec -it claude-dev bash

# 1. HAPI — connects this runner to your hapi.run account
hapi auth login

# 2. Claude Code — subscription device-code flow
claude
#   (follow prompts, pick "Claude Pro/Max subscription")

# 3. GitHub — for cloning/pushing your repos
gh auth login
#   (pick HTTPS, authenticate with browser, scope: repo,workflow)

# 4. Clone a project to work on
cd /workspace
gh repo clone <your-org>/<your-repo>

# 5. Restart to auto-start hapi runner
exit
docker restart claude-dev
```

## Daily use

From phone/laptop, open [app.hapi.run](https://app.hapi.run) — your `claude-dev` runner appears in Machines. Spawn a Claude session targeting `/workspace/<project>`.

## Maintenance

Update Claude Code + HAPI to latest:
```bash
docker exec -it claude-dev bash -c "npm update -g @anthropic-ai/claude-code @twsxtd/hapi"
docker restart claude-dev
```

Rebuild image from scratch (picks up Dockerfile changes):
```bash
# in Coolify UI: redeploy with "Force rebuild"
```

## Volumes (persistent across restarts / redeploys)

- `claude-dev-workspace` — `/workspace` — your git clones, edits
- `claude-dev-home` — `/root` — auth tokens for hapi, claude, gh; shell history; git config

To back up:
```bash
docker run --rm -v claude-dev-workspace:/src -v $PWD:/dst alpine \
  tar czf /dst/workspace-backup.tgz -C /src .
```
