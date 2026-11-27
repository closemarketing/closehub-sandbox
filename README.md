# closehub-sandbox

Local WordPress sandboxes for [Claude Code](https://claude.com/claude-code), without leaving Claude.

One command creates a WordPress site on the **PHP built-in server + SQLite** (no Docker, no MySQL),
mounts the plugin or theme you are working on, writes `.claude/launch.json` and opens the site in
Claude's built-in browser.

## Install

```bash
/plugin marketplace add closemarketing/closehub-sandbox
/plugin install closehub-sandbox@closehub-sandbox
```

## Requirements

- **PHP ≥ 8.1** with `pdo_sqlite`, and **[WP-CLI](https://wp-cli.org/#installing)**: default backend.
- Or **Node.js**: [WordPress Playground](https://wordpress.github.io/wordpress-playground/) backend.
- macOS or Linux (Windows through WSL).

## Usage

From the root of a plugin or theme repo:

```
/closehub-sandbox:wp-local
```

Or just ask: *"spin up a local WordPress for this plugin"*.

Options:

| Flag | Default | |
|---|---|---|
| `[name]` | folder name | Site name |
| `--dir PATH` | asked every time | Where WordPress is installed |
| `--type plugin\|theme\|none` | from `AGENTS.md`, else auto | What to mount and activate |
| `--backend php\|playground` | `php` if PHP + WP-CLI exist | Server backend |
| `--port N` | first free from 8080 | Local port |
| `--wp-version VER` | `latest` | WordPress version |
| `--title "…"` | `<name> (sandbox)` | Site title |
| `--locale es_ES` | `en_US` | WordPress language |

### What it does

1. Reads your project's `AGENTS.md` (or `CLAUDE.md`) to know whether the repo is a plugin, a theme or
   neither. Without it, it detects `Plugin Name:` / `Theme Name:` headers.
2. **Asks where to create the site**: the current folder when it is empty and you are building a
   website (e.g. you made `~/Studio/my-shop` and ran the command there), `~/SandBox/<name>`
   (change the base with `CLOSEHUB_SANDBOX_HOME`) or any path. A plugin/theme repo is never used as the
   site folder, because it is mounted into the site.
   For a website it also asks what the site is about, the kind of site and the language, and
   writes an `AGENTS.md` for it.
3. Installs WordPress core,
   the official [SQLite Database Integration](https://wordpress.org/plugins/sqlite-database-integration/)
   drop-in, pretty permalinks, `WP_ENVIRONMENT_TYPE=local`, debug log on.
4. Symlinks your repo into `wp-content/plugins` or `wp-content/themes` and activates it.
5. Asks which plugin and theme **repositories** to download and clones them straight into
   `wp-content/plugins/<slug>` or `wp-content/themes/<slug>` (no symlink), running `composer install`
   when needed. On a clone it suggests the repositories of the plugins/theme that aren't on
   WordPress.org; on a website, the ones named like the site. Work there is committed and pushed from
   that folder.
6. Adds a `closehub-sandbox-<name>` entry to `.claude/launch.json` (other entries are kept) and starts it
   with `preview_start`.

Log in to `/wp-admin/` with **`admin` / `password`**. Override with the `CLOSEHUB_SANDBOX_ADMIN_USER` and
`CLOSEHUB_SANDBOX_ADMIN_PASSWORD` environment variables before creating the site. The server only listens on
`127.0.0.1`, which is what makes a fixed login acceptable: don't expose a sandbox on the network.

### Migrating WordPress Studio and LocalWP sites

```
/closehub-sandbox:wp-migrate
```

Lists the sites registered in WordPress Studio and LocalWP, asks which ones to migrate and converts
them **in place**:

- `wp-config.php` and the database are backed up first to `<site>/.closehub-sandbox-backup-<time>/`.
- Studio sites already use SQLite: only the sandbox config is added. Stop them in Studio first.
- Local sites use MySQL: start them in Local, and their database is dumped (PHP `mysqli`, no
  `mysqldump` needed) and imported into SQLite.
- Custom domains (`*.wp.local`, `*.local`) become `http://localhost:<port>`; Studio sites keep their
  port. Login becomes `admin` / `password`; other users are kept.
- Each site gets its own `.claude/launch.json`: open Claude Code in the site folder to work on it.

Studio and Local stop serving migrated sites. To undo, restore `wp-config.php` and the database from
the backup folder and delete `.env`, `.closehub-sandbox-bin/` and `closehub-sandbox-env.php`.

### Removing a sandbox

```
/closehub-sandbox:wp-remove
```

It asks which sandbox and confirms (deletion is permanent, database included), stops its server,
removes its `.claude/launch.json` entry and deletes the site. A mounted plugin/theme repo is never
touched: only its symlink inside the site goes. Repositories cloned into the site are deleted with
it, so removal stops if any of them has uncommitted or unpushed work. If you delete a site folder by hand, the next
`/closehub-sandbox:wp-local` notices the stale entry and cleans it up.

### Useful commands

```bash
wp --path=~/SandBox/<name> plugin list          # WP-CLI against the sandbox
tail -f ~/SandBox/<name>/wp-content/debug.log    # PHP notices and errors
bash ~/SandBox/<name>/.closehub-sandbox-bin/serve.sh    # start the server outside the Claude app
```

## Limits

- SQLite: plugins with raw MySQL-specific SQL may fail. Not meant for performance testing.
- The Playground backend does not keep WordPress state between runs.
- `preview_start` exists in the Claude desktop app; in the CLI, run `serve.sh` yourself.

## Cloning a live site

```
/closehub-sandbox:wp-local --from example.com
```

Requires the site connected over MCP with [CloseHub Connector](https://wordpress.org/plugins/closehub-connector/)
and the `closehub-connector-export` addon. The database is downloaded in chunks with a short-lived
ticket, imported into SQLite, production URLs are replaced and the same plugins/theme are installed
from WordPress.org (premium ones are reported as pending).
Production-only plugins (cache, security/anti-spam, SMTP, CDN, backups, management agents —
see [`templates/production-plugins.txt`](templates/production-plugins.txt)) are left out of the copy;
you can keep any of them when Claude asks.

Clones are locked down: outgoing email and every outgoing HTTP request except WordPress.org are
blocked (and logged to `wp-content/debug.log`), WP-Cron is off, and the dump is deleted after the
import. API keys of integrations are copied as they are — that's why outgoing HTTP is blocked.
Allow a host with `CLOSEHUB_SANDBOX_ALLOW_HOSTS=api.example.com` in the site `.env`.

## Roadmap

- Files: uploads and premium plugins/themes through the export addon.

## Development

See [AGENTS.md](AGENTS.md).

```bash
shellcheck -x scripts/*.sh
bats tests/
claude --plugin-dir .
```

## Authors

Made by [Close Marketing](https://close.marketing) — WordPress plugins at
[close.technology](https://close.technology).

## License

GPL-2.0-or-later.
