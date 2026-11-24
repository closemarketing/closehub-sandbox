# AGENTS.md — {{SITE_TITLE}}

## Overview

{{SITE_DESCRIPTION}}

- **Kind of site:** {{SITE_KIND}}
- **Language:** {{SITE_LANGUAGE}}
- **Project type:** WordPress website (not a plugin or theme repo). Agents reading this file should
  treat the directory as a site: content, theme choice, plugins and configuration.

## Local environment

This is a local sandbox created with [sandboxwp-ai](https://github.com/closemarketing/sandboxwp-ai):
WordPress on the PHP built-in server with SQLite. No MySQL, no Docker.

| | |
|---|---|
| Site directory | `{{SITE_DIR}}` |
| URL | {{SITE_URL}} |
| Admin | {{SITE_URL}}/wp-admin/ — `{{ADMIN_USER}}` / `{{ADMIN_PASSWORD}}` |
| Start / stop | `preview_start` / `preview_stop` with `{{LAUNCH_NAME}}` (`.claude/launch.json`) |
| Start outside the Claude app | `bash {{SITE_DIR}}/.sandboxwp-bin/serve.sh` |
| Database | SQLite in `wp-content/database/` |
| PHP errors | `wp-content/debug.log` |

## Working on the site

- WP-CLI: `wp --path="{{SITE_DIR}}" <command>` (e.g. `plugin install woocommerce --activate`).
- Build content and structure with WordPress itself (pages, posts, blocks, theme.json), not with
  static `.html` files in the site root.
- The admin login is a fixed local-only login: never reuse it anywhere else and never expose this
  server beyond `127.0.0.1`.

## Limits

- SQLite: plugins with raw MySQL-specific SQL can fail. Not for performance testing.
- This is not the production site. Moving it to a host needs a MySQL export/migration.
