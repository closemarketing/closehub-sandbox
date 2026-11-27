# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org).

## [Unreleased]

### Added

- `/closehub-sandbox:wp-migrate` and `migrate.sh`: migrate WordPress Studio and LocalWP sites to
  closehub-sandbox in place, with a backup of `wp-config.php` and the database. Local's MySQL
  database is dumped (`mysql-dump.php`, PHP mysqli) and imported into SQLite; custom domains become
  `localhost:<port>` and the login `admin` / `password`.

### Changed

- The SQLite drop-in install moved to `lib.sh` (`sbx_install_sqlite`), shared by setup and migration.

## [0.2.0] - 2026-11-25

### Added

- The first question round asks which plugin and theme repositories to download and where each goes;
  `repos.sh` clones them into `wp-content/plugins|themes/<slug>` (real checkouts, `composer install`
  when needed, build steps reported). Clones suggest the repos of non-WordPress.org plugins/theme.

### Changed

- `remove.sh` stops when a repository cloned into the site has uncommitted or unpushed work
  (`--discard-repo-changes` to delete anyway).

## [0.1.0] - 2026-11-25

First release.

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
- Production-only plugins (cache, security/anti-spam such as WP Armour, SMTP, CDN, backups, management agents) are dropped from clones; `--keep-plugins` / `--remove-plugins` / `--print-removed`.
- `closehub-sandbox-safety` mu-plugin and `DISABLE_WP_CRON` on clones: outgoing email and HTTP (except WordPress.org) blocked and logged.
- bats tests, ShellCheck and a real-install smoke test in CI (PHP 8.1 and 8.3).
