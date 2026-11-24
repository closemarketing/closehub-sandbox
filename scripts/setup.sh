#!/usr/bin/env bash
# Create a local WordPress sandbox for a project.
#
# Usage: setup.sh [--project DIR] [--dir SITE_DIR] [--name NAME] [--type auto|plugin|theme|none]
#                 [--backend auto|php|playground] [--port N] [--wp-version VER]
#                 [--title "Site title"] [--locale es_ES]
#
# --dir is where WordPress is installed (default ~/SandBox/<name>). It must be empty (only
# .claude, .git*, AGENTS.md, CLAUDE.md, README.md, .DS_Store allowed) and, for a plugin/theme
# project, outside the project (the project is symlinked into the site).
# Prints KEY=value lines on stdout (SANDBOXWP_SITE, SANDBOXWP_URL, ...) for the caller.
# Admin login is always admin / password (override with SANDBOXWP_ADMIN_USER / SANDBOXWP_ADMIN_PASSWORD).
# Acceptable only because the server binds to 127.0.0.1: never expose a sandbox on the network.
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

PROJECT="$PWD"
SITE_DIR=""
NAME=""
TYPE="auto"
BACKEND="auto"
PORT=""
WP_VERSION="latest"
TITLE=""
LOCALE="en_US"

while [ $# -gt 0 ]; do
	case "$1" in
	--project) PROJECT="${2:?}"; shift 2 ;;
	--dir) SITE_DIR="${2:?}"; shift 2 ;;
	--name) NAME="${2:?}"; shift 2 ;;
	--type) TYPE="${2:?}"; shift 2 ;;
	--backend) BACKEND="${2:?}"; shift 2 ;;
	--port) PORT="${2:?}"; shift 2 ;;
	--wp-version) WP_VERSION="${2:?}"; shift 2 ;;
	--title) TITLE="${2:?}"; shift 2 ;;
	--locale) LOCALE="${2:?}"; shift 2 ;;
	-h | --help) usage; exit 0 ;;
	*) sbx_die "unknown argument: $1 (see --help)" ;;
	esac
done

[ -d "$PROJECT" ] || sbx_die "project directory not found: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
if [ -n "$SITE_DIR" ]; then
	SITE_DIR="$(sbx_abspath "$SITE_DIR")"
	[ -n "$NAME" ] || NAME="$(basename "$SITE_DIR")"
fi
[ -n "$NAME" ] || NAME="$(basename "$PROJECT")"
NAME="$(sbx_slug "$NAME")"
[ -n "$NAME" ] || sbx_die "could not derive a site name; pass --name"

# --type wins; auto falls back to file detection.
case "$TYPE" in
auto)
	TYPE="$(sbx_detect_type "$PROJECT")"
	[ "$TYPE" != ambiguous ] || sbx_die "project looks like both a plugin and a theme; pass --type plugin|theme"
	;;
plugin | theme | none) ;;
*) sbx_die "invalid --type: $TYPE" ;;
esac

case "$BACKEND" in
auto)
	if sbx_php_ok && sbx_has wp; then
		BACKEND=php
	elif sbx_has npx; then
		BACKEND=playground
		sbx_warn "PHP >= $SBX_MIN_PHP + WP-CLI not found; falling back to the Playground backend"
	else
		sbx_die "need PHP >= $SBX_MIN_PHP and WP-CLI (https://wp-cli.org), or Node.js for the Playground backend"
	fi
	;;
php)
	sbx_php_ok || sbx_die "PHP >= $SBX_MIN_PHP is required for the php backend"
	sbx_has wp || sbx_die "WP-CLI is required for the php backend: https://wp-cli.org/#installing"
	;;
playground) sbx_has npx || sbx_die "Node.js (npx) is required for the playground backend" ;;
*) sbx_die "invalid --backend: $BACKEND" ;;
esac

SITE="${SITE_DIR:-$(sbx_home)/$NAME}"
ENV_FILE="$SITE/.env"

# A plugin/theme is symlinked into the site: a site inside the project would be a symlink loop.
if [ "$TYPE" != none ]; then
	case "$SITE/" in
	"$PROJECT/"*) sbx_die "the site can't live inside the $TYPE it mounts ($PROJECT); choose a directory outside it" ;;
	esac
fi

emit() {
	printf 'SANDBOXWP_SITE=%s\n' "$SITE"
	printf 'SANDBOXWP_NAME=%s\n' "$NAME"
	printf 'SANDBOXWP_PORT=%s\n' "$(sbx_env_get "$ENV_FILE" SANDBOXWP_PORT)"
	printf 'SANDBOXWP_URL=%s\n' "$(sbx_env_get "$ENV_FILE" WP_HOME)"
	printf 'SANDBOXWP_BACKEND=%s\n' "$(sbx_env_get "$ENV_FILE" SANDBOXWP_BACKEND)"
	printf 'SANDBOXWP_TYPE=%s\n' "$(sbx_env_get "$ENV_FILE" SANDBOXWP_TYPE)"
	printf 'SANDBOXWP_ENV=%s\n' "$ENV_FILE"
	printf 'SANDBOXWP_ADMIN_USER=%s\n' "$(sbx_env_get "$ENV_FILE" SANDBOXWP_ADMIN_USER)"
	printf 'SANDBOXWP_ADMIN_PASSWORD=%s\n' "$(sbx_env_get "$ENV_FILE" SANDBOXWP_ADMIN_PASSWORD)"
}

# Re-running on an existing sandbox is a no-op: report it instead of reinstalling.
# Only a .env written by us counts; a project's own .env (Laravel, etc.) must not.
if [ -n "$(sbx_env_get "$ENV_FILE" SANDBOXWP_NAME 2>/dev/null || true)" ]; then
	sbx_info "sandbox '$NAME' already exists at $SITE; reusing it"
	emit
	exit 0
fi

if [ -d "$SITE" ]; then
	if [ -f "$SITE/wp-config.php" ] || [ -f "$SITE/wp-load.php" ]; then
		sbx_die "$SITE already contains a WordPress install not created by sandboxwp-ai (WordPress Studio, Local...?); choose another directory"
	fi
	sbx_dir_is_free "$SITE" || sbx_die "$SITE is not empty; choose an empty directory or a new one"
fi

if [ -z "$PORT" ]; then
	PORT="$(sbx_free_port "$SBX_DEFAULT_PORT")" || sbx_die "no free port found from $SBX_DEFAULT_PORT"
fi
URL="http://localhost:$PORT"

mkdir -p "$SITE"
# Site created inside a git checkout: keep the config, database and helpers out of commits.
if [ -d "$SITE/.git" ]; then
	for entry in .env .sandboxwp-bin/ wp-content/database/ wp-content/debug.log; do
		grep -qxF "$entry" "$SITE/.gitignore" 2>/dev/null || printf '%s\n' "$entry" >>"$SITE/.gitignore"
	done
fi
# serve.sh, lib.sh and router.php live inside the site so launch.json survives plugin updates.
mkdir -p "$SITE/.sandboxwp-bin"
cp "$SBX_ROOT/scripts/serve.sh" "$SBX_ROOT/scripts/lib.sh" "$SBX_ROOT/scripts/router.php" "$SITE/.sandboxwp-bin/"
chmod +x "$SITE/.sandboxwp-bin/serve.sh"

ADMIN_USER="${SANDBOXWP_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${SANDBOXWP_ADMIN_PASSWORD:-password}"
TMP_ENV="$SITE/.env.partial"
rm -f "$TMP_ENV"
sbx_env_set "$TMP_ENV" SANDBOXWP_NAME "$NAME"
sbx_env_set "$TMP_ENV" SANDBOXWP_BACKEND "$BACKEND"
sbx_env_set "$TMP_ENV" SANDBOXWP_TYPE "$TYPE"
sbx_env_set "$TMP_ENV" SANDBOXWP_PROJECT "$PROJECT"
sbx_env_set "$TMP_ENV" SANDBOXWP_PORT "$PORT"
sbx_env_set "$TMP_ENV" WP_HOME "$URL"
sbx_env_set "$TMP_ENV" WP_SITEURL "$URL"
sbx_env_set "$TMP_ENV" WP_ENVIRONMENT_TYPE local
sbx_env_set "$TMP_ENV" SANDBOXWP_LOCALE "$LOCALE"
sbx_env_set "$TMP_ENV" WP_DEBUG true
sbx_env_set "$TMP_ENV" SANDBOXWP_ADMIN_USER "$ADMIN_USER"
sbx_env_set "$TMP_ENV" SANDBOXWP_ADMIN_PASSWORD "$ADMIN_PASSWORD"

if [ "$BACKEND" = playground ]; then
	# Playground keeps its own SQLite database and mounts the project itself (--auto-mount).
	mv "$TMP_ENV" "$ENV_FILE"
	sbx_info "playground sandbox '$NAME' configured (WordPress is created when the server starts)"
	emit
	exit 0
fi

wpcli() { wp --path="$SITE" --skip-plugins --skip-themes "$@"; }

sbx_info "downloading WordPress ($WP_VERSION)"
wp core download --path="$SITE" --version="$WP_VERSION" --quiet >&2

sbx_info "installing the SQLite drop-in"
SQLITE_DIR="$SITE/wp-content/plugins/sqlite-database-integration"
ZIP="$(mktemp)"
curl -fsSL -o "$ZIP" https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip ||
	sbx_die "could not download sqlite-database-integration"
unzip -q -o "$ZIP" -d "$SITE/wp-content/plugins"
rm -f "$ZIP"
[ -f "$SQLITE_DIR/db.copy" ] || sbx_die "unexpected sqlite-database-integration layout (db.copy missing)"
# Relative path via __DIR__ keeps the site movable.
# shellcheck disable=SC2016 # PHP code, not shell
php -r 'file_put_contents($argv[2], strtr(file_get_contents($argv[1]), [$argv[3] => $argv[4], $argv[5] => $argv[6]]));' \
	"$SQLITE_DIR/db.copy" "$SITE/wp-content/db.php" \
	"'{SQLITE_IMPLEMENTATION_FOLDER_PATH}'" "__DIR__ . '/plugins/sqlite-database-integration'" \
	"{SQLITE_PLUGIN}" "sqlite-database-integration/load.php"

cp "$SBX_ROOT/templates/wp-config-env.php" "$SITE/sandboxwp-env.php"
wpcli config create --dbname=wordpress --dbuser=sqlite --dbpass= --skip-check --quiet \
	--extra-php <<'PHP' >&2
require_once __DIR__ . '/sandboxwp-env.php';
PHP

# .env must exist before WP-CLI loads wp-config.php (WP_HOME comes from it).
mv "$TMP_ENV" "$ENV_FILE"

sbx_info "installing WordPress"
wpcli core install --url="$URL" --title="${TITLE:-$NAME (sandbox)}" \
	--admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASSWORD" \
	--admin_email="admin@example.test" --skip-email --quiet >&2
wpcli rewrite structure '/%postname%/' --quiet >&2
if [ "$LOCALE" != en_US ]; then
	sbx_info "installing language $LOCALE"
	wpcli language core install "$LOCALE" --activate --quiet >&2 ||
		sbx_warn "could not install language $LOCALE; the site stays in English"
fi

case "$TYPE" in
plugin)
	ln -sfn "$PROJECT" "$SITE/wp-content/plugins/$NAME"
	wp --path="$SITE" plugin activate "$NAME" --quiet >&2 ||
		sbx_warn "could not activate plugin '$NAME' (missing composer install or build step?)"
	;;
theme)
	ln -sfn "$PROJECT" "$SITE/wp-content/themes/$NAME"
	wp --path="$SITE" theme activate "$NAME" --quiet >&2 ||
		sbx_warn "could not activate theme '$NAME'"
	;;
esac

sbx_info "sandbox '$NAME' ready at $SITE"
emit
