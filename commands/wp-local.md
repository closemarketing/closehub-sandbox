---
description: Create (or reuse) a local WordPress sandbox with SQLite for this project and open it in Claude's browser
argument-hint: "[name] [--from SITE] [--dir PATH] [--type plugin|theme|none] [--backend php|playground] [--port N] [--wp-version VER]"
---

Set up a local WordPress sandbox for the current project and open it in the built-in browser.
Arguments from the user: `$ARGUMENTS` (an optional first word without `--` is the site name).

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project root.

With `--from <site>` (a domain or URL), the sandbox is a **copy of that live site's database**:
follow "Cloning a live site" below alongside the normal steps.

## 1. Decide the project type

Read the project's `AGENTS.md` (or `CLAUDE.md` if there is no `AGENTS.md`). It is the source of truth:

- It says the repo is a WordPress plugin → `--type plugin`.
- It says the repo is a WordPress (block) theme → `--type theme`.
- It describes something else → `--type none`.
- No such file, or it doesn't say → omit `--type` (the script detects it from `Plugin Name:` /
  `Theme Name:` headers). If the script reports "both a plugin and a theme", ask the user.

A `--type` passed by the user always wins.

## 2. Ask where to create the site (and, for a website, what it is)

First check for existing sandboxes of this project:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/launch.sh" --project "$PWD" --list
```

- An entry with status `ok` → reuse it: skip to step 3 with its site directory (second column).
- An entry with status `missing` → its site was deleted. Tell the user in one line, remove the stale
  entry (`launch.sh --project "$PWD" --remove <name>`) and continue as for a new sandbox.

**Always ask before creating anything**, unless the user already passed `--dir` or a sandbox is reused.

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

**Repositories to download.** Always ask it (except when reusing a sandbox or with
`--backend playground`, which can't load cloned repos). It decides which plugin and theme
repositories are cloned into the site, and where each one goes. The project repo itself is never in
this list: a plugin/theme project is mounted as usual.

AskUserQuestion takes at most four questions per call. Add it to the same call when there is room;
for a new website (location + three website questions) ask it in a second call right after the
first.

- Build the candidates first, quietly, with `gh` (skip the lookup if `gh` is missing or not logged in):
  - **Clone (`--from`):** every active plugin/theme of the manifest with `on_wporg: false` that is
    not a production-only plugin. For each slug, look for a repository with that name among the
    user's GitHub accounts: owners from `gh api user --jq .login` and `gh api user/orgs --jq '.[].login'`,
    then `gh repo view <owner>/<slug> --json nameWithOwner`. The type comes from the manifest.
  - **Website (type `none`):** repositories matching the site name, e.g.
    `gh search repos <name> --owner <owner> --json fullName --limit 10` for each owner
    (`mitiendademunecas` → `close-mitiendademunecas-theme`). A repository is a theme when it has
    `style.css` with `Theme Name:` (`gh api repos/<owner>/<repo>/contents/style.css`), otherwise a plugin.
  - **Plugin/theme project:** no lookup; the question only offers "None" or typing repositories.
- Ask with the candidates in the question text, one per line as `owner/repo → wp-content/themes/<slug>`
  (or `plugins/<slug>`). The folder must be the slug WordPress expects (the manifest slug in a clone),
  even when the repository has another name.
- Options: "All of them" (recommended when there are candidates) · "Only the theme" (when one is a
  theme) · "None". "Other" lets the user list repositories by hand (`owner/repo`, optionally
  `@branch`, and whether each is a plugin or a theme).
- Say in the question that the repositories are cloned into the site, not linked: work done there
  has to be committed and pushed from that folder.

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

### Clone the chosen repositories

If the user picked any repository, right after `setup.sh` (and, for a clone, before `import.sh`, so
they don't end up as pending):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/repos.sh" --site "<CLOSEHUB_SANDBOX_SITE>" \
  [--theme owner/repo[@branch][=slug]]... [--plugin owner/repo[@branch][=slug]]... [--activate]
```

- Add `=slug` when the repository name differs from the folder WordPress expects.
- Pass `--activate` for a new empty site only; a clone keeps the plugins and theme active in the
  imported database.
- It prints `CLOSEHUB_SANDBOX_REPOS` (what was cloned) and `CLOSEHUB_SANDBOX_REPOS_TODO`
  (`slug:composer-install` or `slug:npm-build` still to run). Offer to run those steps.
- If it fails on access (private repository) or on an existing folder, tell the user why and go on
  with the rest; never delete the existing folder yourself.

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

## Cloning a live site (`--from`)

Needs the site connected over MCP with **CloseHub Connector** plus the private addon
**closehub-connector-export**. The import uses the `php` backend.

**Before step 2:**

1. Find the site's MCP server: call `closehub-list-sites` on the connected CloseHub servers and pick
   the one whose URL matches `--from`. None → tell the user the site isn't connected and stop.
2. Call `closehub-export/db-manifest` on it (direct tool, or `mcp-adapter-execute-ability`).
   If the ability doesn't exist, the addon isn't installed: offer to deploy the
   `closehub-connector-export` zip with the `close-wpdev-deploy` skill. It writes to the live site, so
   only with the user's yes.
3. Save the manifest JSON to a temporary file. It has no secrets.

**In step 2** skip the website questions (the copy brings title, language and content). Add to the
same AskUserQuestion round:

- A one-line summary: source URL, database size (`total_bytes`), number of tables, and the active
  plugins/themes with `on_wporg: false`. Those can't be installed and will be missing for now.
- **Personal data:** "Exact copy" (default, as agreed) or "Anonymize customers, commenters and
  non-admin users".
- **Production-only plugins** (cache, security/anti-spam, SMTP, CDN, backups, management agents)
  are removed from the copy. List the active ones that apply, from
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh" --manifest "<manifest file>" --print-removed`,
  and let the user keep any of them ("Remove them" as the default, "Keep some" → ask which and pass
  `--keep-plugins a,b`). If the user names extra plugins to drop, pass `--remove-plugins c,d`.

Default site name: the source domain as a slug (e.g. `somos174-es`).

**After step 3** (`setup.sh` with `--backend php`, then `repos.sh` for the chosen repositories):

1. Call `closehub-export/create-db-export` with `anonymize` as answered. **The ticket is a secret:**
   never show it, never write it to a file, never put it on a command line. Pass it only as the
   environment variable of the import command.
2. Run, in the foreground with a 15-minute timeout:

```bash
CLOSEHUB_EXPORT_TICKET='<ticket>' bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh" \
  --site "<CLOSEHUB_SANDBOX_SITE>" --manifest "<manifest file>" \
  --base-url "<base_url>" --job "<job_id>" --tables "<comma-separated table names>" \
  [--keep-plugins a,b] [--remove-plugins c,d]
```

3. If it fails on a download (expired ticket, timeout), create a new export job and run it again.
   Downloaded chunks are kept, so it resumes.
4. Call `closehub-export/revoke-export` with the `job_id` once the import succeeded.
5. For a website clone, write `AGENTS.md` (step 6) describing it as a local copy of the source URL,
   with the import date, instead of asking what the site is about.

**In the report** also say:

- Source and date of the copy, and `CLOSEHUB_SANDBOX_PENDING_PLUGINS` / `_THEMES`. Those are not
  on WordPress.org: the copy may look or behave differently until they are added by hand.
- `CLOSEHUB_SANDBOX_REMOVED_PLUGINS`: production-only plugins left out of the copy.
- **Safety is on:** outgoing email and every outgoing HTTP request except WordPress.org are blocked
  and logged to `debug.log`, and WP-Cron is off. Integration API keys were copied as they are, which
  is why outgoing HTTP is blocked (allow a host with `CLOSEHUB_SANDBOX_ALLOW_HOSTS` in the site `.env`).
- The dump was deleted after the import.

## 7. Report

Tell the user, briefly:

- URL and that wp-admin is at `<CLOSEHUB_SANDBOX_URL>/wp-admin/`.
- Site folder (`CLOSEHUB_SANDBOX_SITE`) and backend.
- Which plugin/theme was mounted and activated, or that the site is empty.
- Repositories cloned into the site (`CLOSEHUB_SANDBOX_REPOS`) with their folders, any build step
  left (`CLOSEHUB_SANDBOX_REPOS_TODO`), and that changes there are committed and pushed from those
  folders.
- **Login:** `admin` / `password` (or the `CLOSEHUB_SANDBOX_ADMIN_USER` / `CLOSEHUB_SANDBOX_ADMIN_PASSWORD`
  values the script printed, if the user overrode them).
- Any activation warning from the script (e.g. missing `composer install` or build step).
