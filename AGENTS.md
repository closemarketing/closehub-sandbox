# AGENTS.md — closehub-sandbox

## Overview

`closehub-sandbox` is a **Claude Code plugin** that spins up a local WordPress site without leaving Claude:
no Docker, no MySQL. WordPress runs on the PHP built-in server (`php -S`) with the official
SQLite drop-in (`sqlite-database-integration`), and Claude opens it in its built-in browser through
`.claude/launch.json` + `preview_start`.

Generic and public: it must work for any WordPress developer, not only CLOSE.

### Scope

- **Empty site:** `/closehub-sandbox:wp-local` creates the site, writes `.env` and
  `.claude/launch.json`, mounts the current repo if it is a plugin or theme, and starts the preview.
- **Clone (`--from <site>`):** imports a live site's database through CloseHub Connector +
  `closehub-connector-export` (private addon, MCP abilities `closehub-export/*`). `import.sh`
  downloads the chunks with the export ticket, runs them through the SQLite driver, switches to the
  production table prefix, replaces production URLs, installs the same plugins/theme from
  WordPress.org, and applies the safety layer.
- **Production-only plugins** (cache, security/anti-spam, SMTP, CDN, backups, management agents)
  listed in `templates/production-plugins.txt` are not installed and are removed from
  `active_plugins` on clones. Per import: `--keep-plugins` / `--remove-plugins`; preview with
  `import.sh --manifest M --print-removed`. Add slugs to the list only after checking them on
  WordPress.org (premium ones by folder name).
- **Safety on clones is mandatory:** the `closehub-sandbox-safety` mu-plugin blocks outgoing email
  and every outgoing HTTP request except WordPress.org (integration API keys are copied as they
  are, so nothing may reach ERP/CRM/payment APIs), `DISABLE_WP_CRON` is on, and the dump is deleted
  after import. Anonymizing personal data is opt-in (`anonymize`), as decided. Never weaken this
  layer by default.
- **Planned:** files (uploads, premium plugins/themes) via the export addon. Until then, plugins
  and themes that aren't on WordPress.org are reported as pending.

## Requirements

- PHP >= 8.1 and WP-CLI: default `php` backend.
- Node + `@wp-playground/cli`: `playground` backend, also the fallback when WP-CLI is missing.
- macOS or Linux. Windows only through WSL.

## Architecture

```
.claude-plugin/plugin.json        Plugin manifest (name, version)
.claude-plugin/marketplace.json   Single-plugin marketplace (install from this repo)
commands/wp-local.md              /closehub-sandbox:wp-local — orchestrates the flow below
commands/wp-remove.md             /closehub-sandbox:wp-remove — confirms and deletes a sandbox
skills/closehub-sandbox/SKILL.md      Auto-triggered guidance ("local WordPress", "sandbox"...)
scripts/lib.sh                    Shared helpers: logging, dependency checks, free port, .env I/O
scripts/setup.sh                  Creates the site (core, SQLite drop-in, config, install, mount)
scripts/serve.sh                  Starts the server; this is what launch.json runs
scripts/launch.sh                 .claude/launch.json entries: add (--site), --list (ok|missing), --remove NAME
scripts/remove.sh                 Deletes a sandbox (--yes required; refuses non-sandbox dirs; stops its server)
scripts/import.sh                 --from: download export job, import, URLs, plugins/theme, safety, login
scripts/import-sql.php            Runs a MySQL dump through $wpdb (SQLite driver) via wp eval-file
templates/closehub-sandbox-safety.php  mu-plugin for clones: blocks email and outgoing HTTP (allowlist)
templates/production-plugins.txt   Plugin folders dropped from clones (cache, security, SMTP, backups...)
scripts/router.php                Router for php -S (pretty permalinks, static files)
templates/env.example             Variables written to the site .env
templates/wp-config-env.php       Loads .env into constants from wp-config.php
templates/site-AGENTS.md          AGENTS.md skeleton for website sandboxes (filled by the command)
tests/*.bats                      bats tests for scripts
```

Flow: `setup.sh` → `launch.sh` → `preview_start` (Claude tool) → `serve.sh` runs under the preview.

Layout created on disk:

```
~/SandBox/<name>/                 WordPress install (override base dir with CLOSEHUB_SANDBOX_HOME)
<site>/.env                      Port, URLs, admin login (chmod 600)
<site>/.closehub-sandbox-bin/            Copies of serve.sh, lib.sh, router.php (launch.json points here)
<site>/AGENTS.md                  Only for websites (type none): what the site is, how to run it
<project>/.claude/launch.json     "closehub-sandbox-<name>" configuration
```

### Where the site goes: always the user's choice

The command **asks before creating anything** (unless `--dir` was given or a sandbox already exists):

1. The current directory, offered first only when the project type is `none` and the directory is
   empty apart from `.claude`, `.git*`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `.DS_Store`
   (e.g. the user made `~/Studio/my-shop` and ran the command there).
2. `~/SandBox/<name>` (base dir overridable with `CLOSEHUB_SANDBOX_HOME`).
3. Any path the user types.

`setup.sh --dir` enforces the rules: the directory must be empty (same allowlist), must not hold a
WordPress install it didn't create (Studio, Local...), and for plugin/theme projects must be outside
the project, which is symlinked into the site (a site inside it would be a symlink loop). Inside a
git checkout it adds `.env`, `.closehub-sandbox-bin/`, `wp-content/database/` to `.gitignore`.

The launch.json points at the copied `serve.sh` inside the site, so it keeps working when the plugin
is updated.

### Website AGENTS.md

When the type is `none` (a website, not a plugin/theme) and the site has no `AGENTS.md`, the command
asks what the website is about (business, kind of site, language) together with the location, passes
`--title`/`--locale` to `setup.sh`, and writes `<site>/AGENTS.md` from `templates/site-AGENTS.md`.
An existing `AGENTS.md` is never overwritten.

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
- **Never** commit secrets, `.env` or client data.
- **Admin login is always `admin` / `password`** (overridable with `CLOSEHUB_SANDBOX_ADMIN_USER` /
  `CLOSEHUB_SANDBOX_ADMIN_PASSWORD`). This is deliberate for local development and safe only because the
  server binds to `127.0.0.1`. Never bind to `0.0.0.0` or add tunnelling/sharing features.
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
`/closehub-sandbox:wp-local` → preview opens → `wp-login.php` answers 200 → login works → the repo
plugin is active → a pretty permalink resolves. Repeat with `--backend playground` when touching it.

## Git workflow

- Branch off `main`; never push directly to it.
- Open a PR (in Spanish) with `gh pr create`. Don't merge with failing required checks.
- Use `gh`, not the GitHub MCP.

## Release

This repo **is** the marketplace (`.claude-plugin/marketplace.json`, `source: "./"`) and it is
public: whatever is on `main` is what users get. Claude Code only offers an update when the
`version` changes, so every user-visible change ships with a version bump. Never release without it.

### While developing

- Every PR with a user-visible change adds a line under `## [Unreleased]` in `CHANGELOG.md`
  (`Added` / `Changed` / `Fixed` / `Removed`). Internal-only changes (tests, CI) don't need one.
- Public repo: no client names, domains, customer data or secrets in code, fixtures, commits or PR
  descriptions. Use `example.com` / `example.test` in fixtures.

### Cutting a release

1. Branch `release/X.Y.Z` off an up-to-date `main`. Semver: `Z` for fixes, `Y` for new features or
   flags, `X` for breaking changes (removed flags, changed `.env` keys, changed site layout).
2. Bump `version` to `X.Y.Z` in **both** files (they must match):
   - `.claude-plugin/plugin.json`
   - the `closehub-sandbox` entry in `.claude-plugin/marketplace.json`
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a new empty
   `## [Unreleased]` above it.
4. If the release changes what users run (requirements, flags, commands, safety layer), update
   `README.md` and the skill/commands to match.
5. Check: `claude plugin validate .`, `shellcheck -x scripts/*.sh`, `bats tests/`.
6. PR in Spanish (`Release X.Y.Z`), CI green, merge.
7. Tag the merge commit on `main` and publish the GitHub release with the changelog section as notes:
   ```bash
   git checkout main && git pull --ff-only
   git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <changelog section>
   ```
8. Tell the team to update (below).

### How users install and update

```
/plugin marketplace add closemarketing/closehub-sandbox
/plugin install closehub-sandbox@closehub-sandbox
```

Update: `/plugin marketplace update closehub-sandbox`, then update the plugin from the `/plugin`
menu (or enable auto-update for this marketplace there).

## Known limits

- SQLite drop-in: plugins with raw MySQL-specific SQL can fail. Not for performance testing.
- `php -S` is single-process unless `PHP_CLI_SERVER_WORKERS` is set; `serve.sh` sets it so
  loopback requests and WP-Cron don't deadlock.
- `preview_start` exists only in the Claude desktop app. In the plain CLI, run `scripts/serve.sh` directly.
