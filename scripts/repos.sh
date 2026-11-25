#!/usr/bin/env bash
# Clone plugin and theme repositories straight into a sandbox (no symlink): the checkout lives in
# wp-content/plugins/<slug> or wp-content/themes/<slug> and is worked on there.
#
# Usage: repos.sh --site SITE_DIR [--plugin SOURCE]... [--theme SOURCE]... [--activate]
#
# SOURCE      owner/name, owner/name@branch, or a git URL (https, ssh, file), optionally followed by
#             =slug to choose the folder name (default: the repository name).
#             Examples: closemarketing/frontblocks-pro  closemarketing/my-theme@develop=my-theme
# --activate  Activate what was cloned (empty sites). Clones of a live site keep their imported
#             active plugins and theme, so the command doesn't pass it there.
#
# A folder that already holds a checkout of the same repository is left as it is. Any other
# existing folder (e.g. a WordPress.org copy) is refused: this script never deletes files.
# Prints CLOSEHUB_SANDBOX_REPOS=type:slug ... and CLOSEHUB_SANDBOX_REPOS_TODO=slug:step ... (build
# steps left to do).
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

SITE=""
ACTIVATE=0
REPOS=()
while [ $# -gt 0 ]; do
	case "$1" in
	--site) SITE="${2:?}"; shift 2 ;;
	--plugin) REPOS+=("plugin	${2:?}"); shift 2 ;;
	--theme) REPOS+=("theme	${2:?}"); shift 2 ;;
	--activate) ACTIVATE=1; shift ;;
	-h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) sbx_die "unknown argument: $1" ;;
	esac
done

[ -n "$SITE" ] || sbx_die "--site is required"
[ -d "$SITE" ] || sbx_die "site directory not found: $SITE"
SITE="$(cd "$SITE" && pwd)"
[ -n "$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_NAME 2>/dev/null || true)" ] ||
	sbx_die "$SITE is not a closehub-sandbox site (no CLOSEHUB_SANDBOX_NAME in .env)"
[ "${#REPOS[@]}" -gt 0 ] || sbx_die "nothing to clone: pass --plugin or --theme"
sbx_has git || sbx_die "git is required"
# Playground runs a fresh WordPress that only mounts the project: cloned repos would be invisible.
[ "$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_BACKEND 2>/dev/null || echo php)" = php ] ||
	sbx_die "cloning repositories needs the php backend (this sandbox uses Playground)"

# Same normalisation as GitHub: case and a trailing .git don't matter.
same_remote() {
	local a b
	a="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's#\.git$##' -e 's#^git@github\.com:#https://github.com/#')"
	b="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]' | sed -e 's#\.git$##' -e 's#^git@github\.com:#https://github.com/#')"
	[ "$a" = "$b" ]
}

CLONED=""
TODO=""
for entry in "${REPOS[@]}"; do
	type="${entry%%	*}"
	src="${entry#*	}"

	slug=""
	case "$src" in *=*) slug="${src##*=}"; src="${src%=*}" ;; esac
	branch=""
	case "$src" in
	*://* | git@*) ;; # a URL: '@' may be part of it
	*@*) branch="${src##*@}"; src="${src%@*}" ;;
	esac
	case "$src" in
	*://* | git@*) url="$src" ;;
	*/*) url="https://github.com/$src.git" ;;
	*) sbx_die "invalid repository '$src': use owner/name or a git URL" ;;
	esac
	[ -n "$slug" ] || slug="$(basename "${src%.git}")"
	printf '%s' "$slug" | grep -qE '^[A-Za-z0-9._-]+$' || sbx_die "invalid folder name '$slug'"

	dest="$SITE/wp-content/${type}s/$slug"
	if [ -e "$dest" ] || [ -L "$dest" ]; then
		current="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
		if [ -n "$current" ] && same_remote "$current" "$url"; then
			sbx_info "$type '$slug' already cloned, left as it is"
		else
			sbx_die "wp-content/${type}s/$slug already exists and is not a checkout of $src; move it away first"
		fi
	else
		mkdir -p "$(dirname "$dest")"
		args=(clone --quiet)
		[ -n "$branch" ] && args+=(--branch "$branch")
		# gh reuses the user's GitHub login for private repositories.
		if [ "$url" = "https://github.com/$src.git" ] && sbx_has gh; then
			gh repo clone "$src" "$dest" -- "${args[@]:1}" >&2 || sbx_die "could not clone $src (no access?)"
		else
			git "${args[@]}" "$url" "$dest" >&2 || sbx_die "could not clone $url (no access?)"
		fi
		sbx_info "cloned $src into wp-content/${type}s/$slug"
	fi

	# Production dependencies the code needs to load. Build steps are only reported.
	if [ -f "$dest/composer.json" ] && [ ! -d "$dest/vendor" ]; then
		if sbx_has composer; then
			composer install --working-dir="$dest" --no-interaction --quiet >&2 ||
				TODO="$TODO $slug:composer-install"
		else
			TODO="$TODO $slug:composer-install"
		fi
	fi
	if [ -f "$dest/package.json" ] && grep -q '"build"' "$dest/package.json" &&
		[ ! -d "$dest/build" ] && [ ! -d "$dest/dist" ] && [ ! -d "$dest/assets/build" ]; then
		TODO="$TODO $slug:npm-build"
	fi

	# A site that is itself a git checkout must not pick up the cloned repos.
	if [ -d "$SITE/.git" ]; then
		line="/wp-content/${type}s/$slug/"
		grep -qxF "$line" "$SITE/.gitignore" 2>/dev/null || printf '%s\n' "$line" >>"$SITE/.gitignore"
	fi

	if [ "$ACTIVATE" = 1 ]; then
		if [ "$type" = plugin ]; then
			wp --path="$SITE" plugin activate "$slug" --quiet >&2 ||
				sbx_warn "could not activate plugin '$slug' (missing composer install or build step?)"
		else
			wp --path="$SITE" theme activate "$slug" --quiet >&2 || sbx_warn "could not activate theme '$slug'"
		fi
	fi

	CLONED="$CLONED $type:$slug"
done

printf 'CLOSEHUB_SANDBOX_REPOS=%s\n' "${CLONED# }"
printf 'CLOSEHUB_SANDBOX_REPOS_TODO=%s\n' "${TODO# }"
