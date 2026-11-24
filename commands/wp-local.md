---
description: Create (or reuse) a local WordPress sandbox with SQLite for this project and open it in Claude's browser
argument-hint: "[name] [--type plugin|theme|none] [--backend php|playground] [--port N] [--wp-version VER]"
---

Set up a local WordPress sandbox for the current project and open it in the built-in browser.
Arguments from the user: `$ARGUMENTS` (an optional first word without `--` is the site name).

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project root.

## 1. Decide the project type

Read the project's `AGENTS.md` (or `CLAUDE.md` if there is no `AGENTS.md`). It is the source of truth:

- It says the repo is a WordPress plugin → `--type plugin`.
- It says the repo is a WordPress (block) theme → `--type theme`.
- It describes something else → `--type none`.
- No such file, or it doesn't say → omit `--type` (the script detects it from `Plugin Name:` /
  `Theme Name:` headers). If the script reports "both a plugin and a theme", ask the user.

A `--type` passed by the user always wins.

## 2. Create the site

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --project "$PWD" [--name NAME] [--type TYPE] [other user flags]
```

- Run it in the foreground with a 5-minute timeout (it downloads WordPress the first time).
- It prints `KEY=value` lines: keep `SANDBOXWP_SITE`, `SANDBOXWP_URL`, `SANDBOXWP_PORT`, `SANDBOXWP_ENV`,
  `SANDBOXWP_ADMIN_USER`, `SANDBOXWP_ADMIN_PASSWORD`.
- If it fails on missing PHP/WP-CLI/Node, show the user the message and the install link; stop.
- Re-running on an existing sandbox reuses it; that is expected.

## 3. Write .claude/launch.json

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/launch.sh" --project "$PWD" --site "<SANDBOXWP_SITE>"
```

It prints the configuration name (`sandboxwp-<name>`) and keeps any other configurations.

## 4. Start and check the preview

- Call `preview_start` with that configuration name. If `preview_start` is not available
  (plain CLI), run `bash "<SANDBOXWP_SITE>/.sandboxwp-bin/serve.sh"` in the background instead.
- Check `<SANDBOXWP_URL>/wp-login.php` answers 200 (open it in the preview or use `curl -s -o /dev/null -w '%{http_code}'`).
- On failure read the server logs (`preview_logs`) and `<SANDBOXWP_SITE>/wp-content/debug.log`.

## 5. Report

Tell the user, briefly:

- URL and that wp-admin is at `<SANDBOXWP_URL>/wp-admin/`.
- Site folder (`SANDBOXWP_SITE`) and backend.
- Which plugin/theme was mounted and activated, or that the site is empty.
- **Login:** `admin` / `password` (or the `SANDBOXWP_ADMIN_USER` / `SANDBOXWP_ADMIN_PASSWORD`
  values the script printed, if the user overrode them).
- Any activation warning from the script (e.g. missing `composer install` or build step).
