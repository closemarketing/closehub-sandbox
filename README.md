# sandboxwp-ai

Local WordPress sandboxes for [Claude Code](https://claude.com/claude-code), without leaving Claude.

One command creates a WordPress site on the **PHP built-in server + SQLite** (no Docker, no MySQL),
mounts the plugin or theme you are working on, writes `.claude/launch.json` and opens the site in
Claude's built-in browser.

## Install

```bash
/plugin marketplace add closemarketing/sandboxwp-ai
/plugin install sandboxwp-ai@sandboxwp-ai
```

## Requirements

- **PHP ≥ 8.1** with `pdo_sqlite`, and **[WP-CLI](https://wp-cli.org/#installing)**: default backend.
- Or **Node.js**: [WordPress Playground](https://wordpress.github.io/wordpress-playground/) backend.
- macOS or Linux (Windows through WSL).

## Usage

From the root of a plugin or theme repo:

```
/sandboxwp-ai:wp-local
```

Or just ask: *"spin up a local WordPress for this plugin"*.

Options:

| Flag | Default | |
|---|---|---|
| `[name]` | repo folder name | Site name (folder under `~/SandBox/`) |
| `--type plugin\|theme\|none` | from `AGENTS.md`, else auto | What to mount and activate |
| `--backend php\|playground` | `php` if PHP + WP-CLI exist | Server backend |
| `--port N` | first free from 8080 | Local port |
| `--wp-version VER` | `latest` | WordPress version |

### What it does

1. Reads your project's `AGENTS.md` (or `CLAUDE.md`) to know whether the repo is a plugin, a theme or
   neither. Without it, it detects `Plugin Name:` / `Theme Name:` headers.
2. Creates the site in `~/SandBox/<name>` (change the base with `SANDBOXWP_HOME`): WordPress core,
   the official [SQLite Database Integration](https://wordpress.org/plugins/sqlite-database-integration/)
   drop-in, pretty permalinks, `WP_ENVIRONMENT_TYPE=local`, debug log on.
3. Symlinks your repo into `wp-content/plugins` or `wp-content/themes` and activates it.
4. Adds a `sandboxwp-<name>` entry to `.claude/launch.json` (other entries are kept) and starts it
   with `preview_start`.

Admin credentials are generated and stored in `~/SandBox/<name>/.env` (mode 600).

### Useful commands

```bash
wp --path=~/SandBox/<name> plugin list          # WP-CLI against the sandbox
tail -f ~/SandBox/<name>/wp-content/debug.log    # PHP notices and errors
bash ~/SandBox/<name>/.sandboxwp-bin/serve.sh    # start the server outside the Claude app
```

## Limits

- SQLite: plugins with raw MySQL-specific SQL may fail. Not meant for performance testing.
- The Playground backend does not keep WordPress state between runs.
- `preview_start` exists in the Claude desktop app; in the CLI, run `serve.sh` yourself.

## Roadmap

- `--from <site>`: import structure and content from a live site through an MCP connector, with
  mandatory sanitising (integration keys emptied, cron and email off, PII anonymised).

## Development

See [AGENTS.md](AGENTS.md).

```bash
shellcheck -x scripts/*.sh
bats tests/
claude --plugin-dir .
```

## License

GPL-2.0-or-later.
