# AGENTS.md — sandboxwp-ai

## Overview

`sandboxwp-ai` is a **Claude Code plugin** that spins up a local WordPress site without leaving Claude:
no Docker, no MySQL. WordPress runs on the PHP built-in server (`php -S`) with the official
SQLite drop-in (`sqlite-database-integration`), and Claude opens it in its built-in browser through
`.claude/launch.json` + `preview_start`.

Generic and public: it must work for any WordPress developer, not only CLOSE.

### Scope

- **v1 (current):** empty local site. `/sandboxwp-ai:wp-local` creates the site, writes `.env` and
  `.claude/launch.json`, mounts the current repo if it is a plugin or theme, and starts the preview.
- **v2 (roadmap):** `--from <site>` imports structure and content from a live site through the
  CloseHub Connector MCP. Sanitising is mandatory and on by default: empty integration API keys
  (ERP/CRM/payment options), disable WP-Cron and outgoing email, anonymise customer/user PII,
  `search-replace` production URLs to the local URL. Never point a sandbox at production services.

## Requirements

- PHP >= 8.1 and WP-CLI: default `php` backend.
- Node + `@wp-playground/cli`: `playground` backend, also the fallback when WP-CLI is missing.
- macOS or Linux. Windows only through WSL.

## Architecture

```
.claude-plugin/plugin.json        Plugin manifest (name, version)
.claude-plugin/marketplace.json   Single-plugin marketplace (install from this repo)
commands/wp-local.md              /sandboxwp-ai:wp-local — orchestrates the flow below
skills/sandboxwp-ai/SKILL.md      Auto-triggered guidance ("local WordPress", "sandbox"...)
scripts/lib.sh                    Shared helpers: logging, dependency checks, free port, .env I/O
scripts/setup.sh                  Creates the site (core, SQLite drop-in, config, install, mount)
scripts/serve.sh                  Starts the server; this is what launch.json runs
scripts/launch.sh                 Merges the sandboxwp entry into .claude/launch.json
scripts/router.php                Router for php -S (pretty permalinks, static files)
templates/env.example             Variables written to the site .env
templates/wp-config-env.php       Loads .env into constants from wp-config.php
tests/*.bats                      bats tests for scripts
```

Flow: `setup.sh` → `launch.sh` → `preview_start` (Claude tool) → `serve.sh` runs under the preview.

Layout created on disk:

```
~/SandBox/<name>/                 WordPress install (override base dir with SANDBOXWP_HOME)
~/SandBox/<name>/.env             Port, URLs, generated admin credentials (chmod 600)
~/SandBox/<name>/.sandboxwp-bin/  Copies of serve.sh, lib.sh, router.php (launch.json points here)
<project>/.claude/launch.json     "sandboxwp-<name>" configuration
```

Sites live outside the project on purpose: the project is symlinked into the site, so a site inside
the project would create a symlink loop and put WordPress core in the repo. The launch.json points
at the copied `serve.sh` inside the site, so it keeps working when the plugin is updated.

### Project type (plugin / theme / none)

The **project's own `AGENTS.md` (or `CLAUDE.md`) is the source of truth** for what is being
developed. The command reads it first and passes `--type plugin|theme|none` to `setup.sh`:

- It says the repo is a WordPress plugin → `--type plugin`.
- It says the repo is a WordPress (block) theme → `--type theme`.
- Anything else, or no WordPress code → `--type none` (empty site).

Only when the project has no `AGENTS.md`/`CLAUDE.md`, or it doesn't state the type, `setup.sh`
falls back to detection: main PHP file with a `Plugin Name:` header → plugin; `style.css` with
`Theme Name:` → theme. If both match, ask the user instead of guessing.

Plugins are symlinked into `wp-content/plugins/` and activated; themes into `wp-content/themes/`
and activated. `--type` always wins over detection.

## Conventions

- **Language:** code, comments, commit messages and docs in **English**. PRs and issues in **Spanish**.
- **Comments:** only for non-obvious logic or decisions, per chunk of related lines — never every line.
- **Bash:** `#!/usr/bin/env bash`, `set -euo pipefail`, quote every expansion, functions in `lib.sh`.
  Must run on both macOS (BSD `sed`, `stat`, bash 3.2) and Linux (GNU). No `sed -i` without a
  portable wrapper, no associative arrays, no `readarray`.
- **No network or global state in tests:** tests stub `wp`, `php` and `npx` via `PATH`.
- **Never** commit secrets, `.env`, generated credentials or client data. Generated credentials live
  only in the site `.env` and are shown to the user once; agents must not repeat them in chat.
- The plugin must never write outside the user's project, except caches managed by WP-CLI/npm.

## Commands

```bash
shellcheck scripts/*.sh          # lint
bats tests/                      # all tests
bats tests/setup.bats            # one file
claude --plugin-dir .            # load the plugin locally for manual E2E
```

### Test Enforcement

- Every change in `scripts/` must be programmatically tested: add or update a bats test, run it and
  confirm it passes.
- Run the minimum tests needed for speed: `bats tests/<file>.bats`.
- Before saying "done": `shellcheck scripts/*.sh` and `bats tests/` must pass.
- CI gate: the `ci` workflow (shellcheck + bats) must be green before merging into `main`.
- Bug fixes need a regression test.

### Manual verification (behaviour bats cannot cover)

After changing the command, skill or server flow, run an E2E in a scratch plugin repo:
`/sandboxwp-ai:wp-local` → preview opens → `wp-login.php` answers 200 → login works → the repo
plugin is active → a pretty permalink resolves. Repeat with `--backend playground` when touching it.

## Git workflow

- Branch off `main`; never push directly to it.
- Open a PR (in Spanish) with `gh pr create`. Don't merge with failing required checks.
- Use `gh`, not the GitHub MCP.

## Release

1. Bump `version` in `.claude-plugin/plugin.json` and the plugin entry in `.claude-plugin/marketplace.json` (semver).
2. Add the entry to `CHANGELOG.md`.
3. Merge the release PR, then tag and publish:
   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   gh release create vX.Y.Z --notes-from-tag
   ```
Users install or update with `/plugin marketplace add closemarketing/sandboxwp-ai` and
`/plugin install sandboxwp-ai@sandboxwp-ai`.

## Known limits

- SQLite drop-in: plugins with raw MySQL-specific SQL can fail. Not for performance testing.
- `php -S` is single-process unless `PHP_CLI_SERVER_WORKERS` is set; `serve.sh` sets it so
  loopback requests and WP-Cron don't deadlock.
- `preview_start` exists only in the Claude desktop app. In the plain CLI, run `scripts/serve.sh` directly.
