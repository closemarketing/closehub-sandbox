# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org).

## [0.1.0] - Unreleased

### Added

- `/closehub-sandbox:wp-local` command and `closehub-sandbox` skill. The command always asks where to create
  the site (current empty folder, `~/SandBox/<name>` or any path) and, for websites, what the site is
  about, its kind and language, then writes the site's `AGENTS.md`.
- `setup.sh --dir`, `--title`, `--locale`: site directory validation (empty, not an existing
  WordPress install, not inside the plugin/theme it mounts).
- `setup.sh`: WordPress + SQLite drop-in site in `~/SandBox/<name>`, `admin` / `password` login
  (overridable via environment), plugin/theme mount and activation. Project type read from the project's `AGENTS.md`,
  with header detection as fallback.
- `serve.sh`: PHP built-in server with workers and a router (pretty permalinks, dotfiles blocked),
  or WordPress Playground backend.
- `launch.sh`: adds (`--site`), lists (`--list`, with `ok`/`missing` status) and removes (`--remove`) `closehub-sandbox-<name>` entries in `.claude/launch.json`. `/wp-local` reuses a live sandbox and cleans up entries whose site was deleted.
- `/closehub-sandbox:wp-remove` and `remove.sh`: delete a sandbox after confirmation (server stopped, entry removed, mounted repos untouched, optional `--keep-project-files`).
- `--from <site>` and `import.sh`: clone a live site's database from a closehub-connector-export job into SQLite (resumable download, production prefix, URL replacement, same plugins/theme from WordPress.org, pending list for premium ones, `admin` / `password` login, dump deleted afterwards).
- `closehub-sandbox-safety` mu-plugin and `DISABLE_WP_CRON` on clones: outgoing email and HTTP (except WordPress.org) blocked and logged.
- bats tests, ShellCheck and a real-install smoke test in CI (PHP 8.1 and 8.3).
