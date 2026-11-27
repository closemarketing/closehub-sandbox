---
description: Migrate WordPress Studio and LocalWP sites to closehub-sandbox, in place
argument-hint: "[site name or folder] [--all]"
---

Migrate local WordPress sites from **WordPress Studio** or **LocalWP** to closehub-sandbox, in their
own folders. Arguments from the user: `$ARGUMENTS` (a site name or folder, or `--all`).

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`.

## 1. List the sites

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate.sh" --list
```

One line per site: `SOURCE NAME WP_ROOT PORT DOMAIN STATUS`. `SOURCE` is `studio` or `local`;
`STATUS` is `ready`, `migrated` (already done) or `missing` (folder deleted). Nothing listed means
neither app is installed or has sites: say so and stop. Show the user a short table of the `ready`
ones (name, app, folder) and how many are already migrated.

## 2. Ask which ones, and confirm

Skip the choice when the arguments already name the sites (`--all` = every `ready` site), but always
confirm. Ask in one AskUserQuestion call, in the user's language:

- Which sites: "All pending (N)" (recommended) · "Choose" (the user types names) · "Cancel".
- Say what migrating does, in the question text:
  - In place, in the same folder. Before changing anything, `wp-config.php` and the database are
    backed up to `<site>/.closehub-sandbox-backup-<time>/`.
  - The site moves to `http://localhost:<port>` (Studio keeps its port; custom domains like
    `*.wp.local` or Local's `*.local` are replaced in the database). Studio or Local stop serving it.
  - Login becomes `admin` / `password`; other users are kept.
- Requirements: **Studio** sites must be **stopped** in Studio (the script refuses if the port is in
  use). **Local** sites must be **started** in Local, because their MySQL database is only reachable
  then.

## 3. Migrate

For each chosen site, one at a time, in the foreground (5-minute timeout each):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate.sh" --site "<WP_ROOT>"
```

- It prints `CLOSEHUB_SANDBOX_SITE`, `_NAME`, `_SOURCE_APP`, `_URL`, `_LAUNCH` and `_BACKUP`.
- If one fails (port in use, Local site not running, unreadable wp-config.php), note the reason and
  go on with the rest. Never delete or edit the backup.
- Don't start the servers of every migrated site: they would all compete for ports and memory.

## 4. Report

A table: site, app, new URL, backup folder, result (migrated / failed and why). Then:

- To work on a site, open Claude Code in its folder and start `closehub-sandbox-<name>` with
  `preview_start` (its `.claude/launch.json` is there), or run
  `bash <site>/.closehub-sandbox-bin/serve.sh <site>`.
- Failed Studio sites: stop them in Studio and run the command again. Failed Local sites: start them
  in Local and run it again.
- To undo a migration: copy `wp-config.php` and the database back from the backup folder (for Local,
  `database.sql` is a MySQL dump of the original database) and delete `.env`,
  `.closehub-sandbox-bin/` and `closehub-sandbox-env.php`.
