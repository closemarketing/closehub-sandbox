---
name: closehub-sandbox
description: "Use this skill to create, start, inspect or remove a local WordPress sandbox (PHP built-in server + SQLite, no Docker/MySQL) for the plugin or theme in the current repo, and preview it in Claude's built-in browser via .claude/launch.json. Triggers on: 'local WordPress', 'WordPress sandbox', 'spin up WordPress', 'test this plugin locally', 'preview this theme', 'entorno local de WordPress', 'monta un WordPress', 'sandbox de WordPress', 'levanta el sitio local', '/wp-local'."
---

# closehub-sandbox

Local WordPress sandboxes for the project in the current directory. They run on `php -S` with the
SQLite drop-in, or on WordPress Playground. **Where the site is created is always the user's choice**:
the current directory when it is empty and not a plugin/theme, `~/SandBox/<name>` by default
(`CLOSEHUB_SANDBOX_HOME` changes the base), or any path they give. Below, `<site>` is that directory
(it is in the `runtimeArgs` of the `closehub-sandbox-*` entry in `.claude/launch.json`).

## Create or reuse a sandbox

Follow the `/closehub-sandbox:wp-local` command (`${CLAUDE_PLUGIN_ROOT}/commands/wp-local.md`). Key rules:

- **Project type comes from the project's `AGENTS.md`/`CLAUDE.md`** (plugin, theme, or none). Pass it
  as `--type`. Only without that file fall back to the script's header detection.
- **Ask where to create the site before running anything** (see step 2 of the command). Never pick
  a directory on your own, and never put the site inside the plugin/theme it mounts.
- Run `scripts/setup.sh --dir <chosen>`, then `scripts/launch.sh`, then `preview_start` with the printed name.
- For a website (type `none`) without `AGENTS.md`: ask what it is about, the kind of site and the
  language in the same question round, and write `<site>/AGENTS.md` from `templates/site-AGENTS.md`.
- Login is always `admin` / `password` (overridable with `CLOSEHUB_SANDBOX_ADMIN_USER` / `CLOSEHUB_SANDBOX_ADMIN_PASSWORD`).

## Day-to-day operations

| Need | How |
|---|---|
| Start a stopped sandbox | `preview_start` with `closehub-sandbox-<name>` (launch.json already exists) |
| Stop it | `preview_stop` |
| WP-CLI on the sandbox | `wp --path="<site>" <command>` (php backend only) |
| PHP errors | `<site>/wp-content/debug.log` (`WP_DEBUG_LOG` on, display off) |
| Port in use | Change `CLOSEHUB_SANDBOX_PORT`, `WP_HOME`, `WP_SITEURL` in the site `.env`, re-run `launch.sh` |
| Remove a sandbox | Confirm with the user first (deletes the database), then `preview_stop`, delete `<site>` (if the site is the project directory itself, delete only the WordPress files, never `.claude`, `.git` or docs) and remove its entry from `.claude/launch.json` |

## Limits to tell the user about when relevant

- SQLite: plugins with raw MySQL-specific SQL can fail; not for performance testing.
- Playground backend: fast to start, but its WordPress state is not persisted between runs.
- Importing a live site (`--from`) is not in v1.

## Safety

- Sandboxes are local-only (`WP_ENVIRONMENT_TYPE=local`). Never configure them with production
  API keys or point integrations (ERP, CRM, payments) at real accounts.
- The router blocks dotfiles (`.env`, `.ht.sqlite`), so the config and the database are not served.
- The fixed `admin` / `password` login is safe only because the server binds to `127.0.0.1`.
  Never bind a sandbox to `0.0.0.0` or expose it through a tunnel.
