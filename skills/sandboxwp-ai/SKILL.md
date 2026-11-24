---
name: sandboxwp-ai
description: "Use this skill to create, start, inspect or remove a local WordPress sandbox (PHP built-in server + SQLite, no Docker/MySQL) for the plugin or theme in the current repo, and preview it in Claude's built-in browser via .claude/launch.json. Triggers on: 'local WordPress', 'WordPress sandbox', 'spin up WordPress', 'test this plugin locally', 'preview this theme', 'entorno local de WordPress', 'monta un WordPress', 'sandbox de WordPress', 'levanta el sitio local', '/wp-local'."
---

# sandboxwp-ai

Local WordPress sandboxes for the project in the current directory. Sites live in `~/SandBox/<name>`
(base dir overridable with `SANDBOXWP_HOME`) and run on `php -S` with the SQLite drop-in, or on
WordPress Playground.

## Create or reuse a sandbox

Follow the `/sandboxwp-ai:wp-local` command (`${CLAUDE_PLUGIN_ROOT}/commands/wp-local.md`). Key rules:

- **Project type comes from the project's `AGENTS.md`/`CLAUDE.md`** (plugin, theme, or none). Pass it
  as `--type`. Only without that file fall back to the script's header detection.
- Run `scripts/setup.sh`, then `scripts/launch.sh`, then `preview_start` with the printed name.
- Never print the generated admin password; point the user to the site `.env`.

## Day-to-day operations

| Need | How |
|---|---|
| Start a stopped sandbox | `preview_start` with `sandboxwp-<name>` (launch.json already exists) |
| Stop it | `preview_stop` |
| WP-CLI on the sandbox | `wp --path="$HOME/SandBox/<name>" <command>` (php backend only) |
| PHP errors | `~/SandBox/<name>/wp-content/debug.log` (`WP_DEBUG_LOG` on, display off) |
| Port in use | Change `SANDBOXWP_PORT`, `WP_HOME`, `WP_SITEURL` in the site `.env`, re-run `launch.sh` |
| Remove a sandbox | Confirm with the user first (deletes the database), then `preview_stop`, delete `~/SandBox/<name>` and remove its entry from `.claude/launch.json` |

## Limits to tell the user about when relevant

- SQLite: plugins with raw MySQL-specific SQL can fail; not for performance testing.
- Playground backend: fast to start, but its WordPress state is not persisted between runs.
- Importing a live site (`--from`) is not in v1.

## Safety

- Sandboxes are local-only (`WP_ENVIRONMENT_TYPE=local`). Never configure them with production
  API keys or point integrations (ERP, CRM, payments) at real accounts.
- The router blocks dotfiles (`.env`, `.ht.sqlite`), so credentials and the database are not served.
