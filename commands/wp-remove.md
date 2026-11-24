---
description: Permanently delete a local WordPress sandbox (stops its server, removes its launch.json entry and its files)
argument-hint: "[name or path]"
---

Delete a sandbox created by `/closehub-sandbox:wp-local`. Arguments from the user: `$ARGUMENTS`
(a sandbox name or a site path; optional).

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`.

## 1. Find the sandbox

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/launch.sh" --project "$PWD" --list
```

Each line is `NAME<TAB>SITE<TAB>ok|missing`. Also consider:

- A path given by the user.
- `~/SandBox/<name>` (or `$CLOSEHUB_SANDBOX_HOME/<name>`) when the user gives only a name.
- The current directory, if it holds a `.env` with `CLOSEHUB_SANDBOX_NAME` (a website sandbox
  created in place).

Only entries with status `missing`: the site is already gone, so just remove the entry
(`launch.sh --project "$PWD" --remove <name>`), say so, and stop.

If several sandboxes match, or none was named and there is more than one, ask which one.

## 2. Confirm (always)

Deletion is permanent: no trash, database included. Ask with AskUserQuestion, naming the site
directory and saying it can't be undone. Options:

- **Delete everything:** the whole site folder.
- **Keep project files:** only when the site folder is also the project folder (it has `.claude`,
  `.git`, `AGENTS.md`, `CLAUDE.md` or `README.md` the user may want). Deletes WordPress and the
  sandbox files and keeps those.
- **Cancel.**

Mention that a mounted plugin/theme repo is not affected (only its symlink inside the site is removed).

## 3. Delete

1. Stop the preview first if it is running: `preview_stop` for that server (if the tool is available).
2. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh" --site "<SITE>" --project "$PWD" [--keep-project-files] --yes
```

Pass `--yes` only after the user confirmed in step 2. The script refuses anything that is not a
closehub-sandbox site, stops a server still listening on the sandbox port, and removes the
`launch.json` entry.

## 4. Report

One or two lines: what was deleted (path) and what was kept, if anything.
