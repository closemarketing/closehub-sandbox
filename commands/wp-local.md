---
description: Create (or reuse) a local WordPress sandbox with SQLite for this project and open it in Claude's browser
argument-hint: "[name] [--dir PATH] [--type plugin|theme|none] [--backend php|playground] [--port N] [--wp-version VER]"
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

## 2. Ask where to create the site (and, for a website, what it is)

**Always ask before creating anything**, unless the user already passed `--dir`, or
`.claude/launch.json` already has a `closehub-sandbox-*` entry for this project (then reuse it: skip to
step 3 with that site's directory from its `runtimeArgs`).

Ask everything in **one** AskUserQuestion call. The first question is the location, with these
options, in this order:

1. **This directory (`$PWD`)**, first and recommended, only when **both**:
   - the type from step 1 is `none`, and
   - the directory is empty apart from `.claude`, `.git*`, `AGENTS.md`, `CLAUDE.md`, `README.md`,
     `.DS_Store` (check with `ls -A`).
   Typical case: the user created an empty folder for the site (e.g. `~/Studio/my-shop`) and ran the
   command from it.
2. **`~/SandBox/<name>`**, the default home for sandboxes (`$CLOSEHUB_SANDBOX_HOME` if set).
3. The user can type any other path ("Other").

If the project is a plugin or theme, don't offer `$PWD`: say in one line that the repo is mounted
into the site, so the site has to live outside it. If `$PWD` is not empty and not a plugin/theme,
don't offer it either and say why (WordPress files would mix with what is there).

**Website questions.** When the type is `none` and there is no `AGENTS.md` describing the site,
add three more questions to the same call:

- **What is the website about?** Offer 2–3 concrete guesses built from the folder name and anything
  the user said (e.g. folder `mitiendademunecas` → "Tienda online de muñecas", "Blog sobre muñecas
  de colección"). The user picks one or types their own ("Other").
- **Kind of site:** online shop (WooCommerce) · corporate / services · blog / content · landing page.
- **Language:** Spanish (`es_ES`) · English (`en_US`) · Catalan (`ca`) · other.

Write the questions in the user's language.

## 3. Create the site

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --project "$PWD" --dir "<chosen dir>" [--name NAME] [--type TYPE] \
  [--title "<short site title>"] [--locale <locale>] [other user flags]
```

For a website, derive `--title` from the answer (e.g. "Mi tienda de muñecas") and pass `--locale`.

- Run it in the foreground with a 5-minute timeout (it downloads WordPress the first time).
- It prints `KEY=value` lines: keep `CLOSEHUB_SANDBOX_SITE`, `CLOSEHUB_SANDBOX_URL`, `CLOSEHUB_SANDBOX_PORT`, `CLOSEHUB_SANDBOX_ENV`,
  `CLOSEHUB_SANDBOX_ADMIN_USER`, `CLOSEHUB_SANDBOX_ADMIN_PASSWORD`.
- If it fails on missing PHP/WP-CLI/Node, show the user the message and the install link; stop.
- Re-running on an existing sandbox reuses it; that is expected.
- If it refuses the directory (not empty, existing WordPress install, inside the plugin/theme),
  tell the user why and ask again; never retry with another directory on your own.

## 4. Write .claude/launch.json

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/launch.sh" --project "$PWD" --site "<CLOSEHUB_SANDBOX_SITE>"
```

It prints the configuration name (`closehub-sandbox-<name>`) and keeps any other configurations.

## 5. Start and check the preview

- Call `preview_start` with that configuration name. If `preview_start` is not available
  (plain CLI), run `bash "<CLOSEHUB_SANDBOX_SITE>/.closehub-sandbox-bin/serve.sh"` in the background instead.
- Check `<CLOSEHUB_SANDBOX_URL>/wp-login.php` answers 200 (open it in the preview or use `curl -s -o /dev/null -w '%{http_code}'`).
- On failure read the server logs (`preview_logs`) and `<CLOSEHUB_SANDBOX_SITE>/wp-content/debug.log`.

## 6. Website AGENTS.md

Only for type `none`, and only if `<CLOSEHUB_SANDBOX_SITE>/AGENTS.md` does not exist (never overwrite):

- Fill `${CLAUDE_PLUGIN_ROOT}/templates/site-AGENTS.md` and write it to `<CLOSEHUB_SANDBOX_SITE>/AGENTS.md`.
- `{{SITE_DESCRIPTION}}`: two or three sentences from the user's answer (what the business does,
  who it is for, main goal of the site). Don't invent facts beyond what the user said.
- The other placeholders come from the answers and from setup.sh's output. No `{{...}}` may remain.
- Write it in the site's language.
- If the kind is "online shop", offer to install WooCommerce (`wp --path=<site> plugin install
  woocommerce --activate`); don't install it without a yes.

## 7. Report

Tell the user, briefly:

- URL and that wp-admin is at `<CLOSEHUB_SANDBOX_URL>/wp-admin/`.
- Site folder (`CLOSEHUB_SANDBOX_SITE`) and backend.
- Which plugin/theme was mounted and activated, or that the site is empty.
- **Login:** `admin` / `password` (or the `CLOSEHUB_SANDBOX_ADMIN_USER` / `CLOSEHUB_SANDBOX_ADMIN_PASSWORD`
  values the script printed, if the user overrode them).
- Any activation warning from the script (e.g. missing `composer install` or build step).
