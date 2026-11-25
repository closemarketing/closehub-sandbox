#!/usr/bin/env bash
# Permanently delete a sandbox: stop its server, drop its launch.json entry, delete its files.
#
# Usage: remove.sh --site SITE_DIR [--project DIR] [--keep-project-files] --yes
#
# --project             Project whose .claude/launch.json has the entry (default: the current dir).
# --keep-project-files  Delete only WordPress and sandbox files, keeping .claude, .git*, AGENTS.md,
#                       CLAUDE.md and README.md (for a site created inside the project folder).
# --yes                 Required: the deletion can't be undone (database included).
# --discard-repo-changes  Delete even if a repository cloned into the site (repos.sh) has
#                       uncommitted changes or commits not pushed. Without it, removal stops.
#
# A mounted plugin/theme is a symlink: removing it never touches the repo it points to.
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

SITE=""
PROJECT="$PWD"
KEEP=0
YES=0
DISCARD=0
while [ $# -gt 0 ]; do
	case "$1" in
	--site) SITE="${2:?}"; shift 2 ;;
	--project) PROJECT="${2:?}"; shift 2 ;;
	--keep-project-files) KEEP=1; shift ;;
	--yes) YES=1; shift ;;
	--discard-repo-changes) DISCARD=1; shift ;;
	-h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) sbx_die "unknown argument: $1" ;;
	esac
done

[ -n "$SITE" ] || sbx_die "--site is required"
[ -d "$SITE" ] || sbx_die "site directory not found: $SITE"
SITE="$(cd "$SITE" && pwd)"

# Only ever delete something setup.sh created.
NAME="$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_NAME 2>/dev/null || true)"
[ -n "$NAME" ] || sbx_die "$SITE is not a closehub-sandbox site (no CLOSEHUB_SANDBOX_NAME in .env); refusing to delete it"
case "$SITE" in
/ | "$HOME" | "$(sbx_home)") sbx_die "refusing to delete $SITE" ;;
esac
[ "$YES" = 1 ] || sbx_die "refusing without --yes: deleting $SITE is permanent (database included)"

# Repositories cloned into the site (not symlinks) may hold work that exists nowhere else:
# uncommitted changes, commits not on any remote (branches or a detached HEAD), or stashes.
if [ "$DISCARD" = 0 ] && sbx_has git; then
	unsaved=""
	for repo in "$SITE"/wp-content/plugins/* "$SITE"/wp-content/themes/*; do
		[ -d "$repo/.git" ] && [ ! -L "$repo" ] || continue
		if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] ||
			[ -n "$(git -C "$repo" log HEAD --branches --not --remotes --oneline 2>/dev/null)" ] ||
			[ -n "$(git -C "$repo" stash list 2>/dev/null)" ]; then
			unsaved="$unsaved ${repo#"$SITE"/}"
		fi
	done
	[ -z "$unsaved" ] || sbx_die "repositories with uncommitted or unpushed work:$unsaved. Commit and push them, or pass --discard-repo-changes"
fi

PORT="$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_PORT || true)"

# 1. Stop its server (php -S or Playground) by port.
if [ -n "$PORT" ] && sbx_has pgrep; then
	pids="$(
		pgrep -f "php -S 127.0.0.1:${PORT} " || true
		pgrep -f "@wp-playground/cli.* --port=${PORT}( |$)" || true
	)"
	if [ -n "$pids" ]; then
		# shellcheck disable=SC2086 # word splitting of the pid list is intended
		kill $pids 2>/dev/null || true
		sbx_info "stopped the server on port $PORT"
	fi
fi

# 2. Drop its launch.json entry.
if [ -d "$PROJECT" ]; then
	bash "$SBX_ROOT/scripts/launch.sh" --project "$PROJECT" --remove "closehub-sandbox-$NAME" >/dev/null 2>&1 || true
fi

# 3. Delete the files. rm -rf removes symlinks themselves, never their targets.
if [ "$KEEP" = 1 ]; then
	for f in "$SITE"/* "$SITE"/.[!.]* "$SITE"/..?*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		case "$(basename "$f")" in
		.claude | .git | .gitignore | .gitattributes | AGENTS.md | CLAUDE.md | README.md) ;;
		*) rm -rf "$f" ;;
		esac
	done
	sbx_info "removed sandbox '$NAME' from $SITE (project files kept)"
else
	rm -rf "$SITE"
	sbx_info "removed sandbox '$NAME' ($SITE)"
fi
