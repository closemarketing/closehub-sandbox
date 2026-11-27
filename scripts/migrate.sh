#!/usr/bin/env bash
# Migrate a WordPress Studio or LocalWP site to closehub-sandbox, in place.
#
# Usage:
#   migrate.sh --list                       Sites registered in Studio and Local, tab-separated:
#                                           SOURCE NAME WP_ROOT PORT DOMAIN STATUS (ready|migrated|missing)
#   migrate.sh --site DIR [--port N] [--name NAME]
#
# DIR is the site folder (Studio: ~/Studio/<site>; Local: ~/Local Sites/<site> or its app/public).
#
# Studio sites already use SQLite: only the sandbox config is added. Local sites run on MySQL: the
# site must be started in Local while migrating; its database is dumped (PHP mysqli) and imported
# into SQLite. In both cases:
#   - wp-config.php and the database are backed up first to <wp_root>/.closehub-sandbox-backup-<time>/
#   - the site URLs become http://localhost:<port> (Studio keeps its port), login admin / password
#   - .env, serve.sh and a closehub-sandbox entry in <wp_root>/.claude/launch.json are written
# The Studio/Local apps are not touched; serving the site from them afterwards is not supported.
#
# Registries: CLOSEHUB_SANDBOX_STUDIO_CONFIG and CLOSEHUB_SANDBOX_LOCAL_CONFIG (comma-separated
# files) override the default locations.
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

STUDIO_CONFIG="${CLOSEHUB_SANDBOX_STUDIO_CONFIG:-$HOME/.studio/config.json,$HOME/.studio/cli.json,$HOME/Library/Application Support/Studio/appdata-v1.json,$HOME/.config/Studio/appdata-v1.json}"
LOCAL_CONFIG="${CLOSEHUB_SANDBOX_LOCAL_CONFIG:-$HOME/Library/Application Support/Local/sites.json,$HOME/.config/Local/sites.json}"

LIST=0
SITE_ARG=""
PORT=""
NAME=""
while [ $# -gt 0 ]; do
	case "$1" in
	--list) LIST=1; shift ;;
	--site) SITE_ARG="${2:?}"; shift 2 ;;
	--port) PORT="${2:?}"; shift 2 ;;
	--name) NAME="${2:?}"; shift 2 ;;
	-h | --help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) sbx_die "unknown argument: $1" ;;
	esac
done

sbx_has php || sbx_die "PHP is required"

SEP="$(printf '\037')"
registry() { php "$SBX_ROOT/scripts/migrate-registry.php" "$STUDIO_CONFIG" "$LOCAL_CONFIG"; }

is_sandbox() { [ -n "$(sbx_env_get "$1/.env" CLOSEHUB_SANDBOX_NAME 2>/dev/null || true)" ]; }

if [ "$LIST" = 1 ]; then
	registry | while IFS="$SEP" read -r source name root port domain _mysql; do
		if [ ! -d "$root" ]; then
			status=missing
		elif is_sandbox "$root"; then
			status=migrated
		else
			status=ready
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$source" "$name" "$root" "$port" "$domain" "$status"
	done
	exit 0
fi

[ -n "$SITE_ARG" ] || sbx_die "--site or --list is required"
[ -d "$SITE_ARG" ] || sbx_die "site directory not found: $SITE_ARG"
ROOT="$(cd "$SITE_ARG" && pwd)"
[ -f "$ROOT/wp-config.php" ] || { [ -f "$ROOT/app/public/wp-config.php" ] && ROOT="$ROOT/app/public"; }
[ -f "$ROOT/wp-config.php" ] || sbx_die "no wp-config.php in $SITE_ARG (or its app/public)"

if is_sandbox "$ROOT"; then
	sbx_info "$ROOT is already a closehub-sandbox site; nothing to do"
	exit 0
fi

# The registry says where the site comes from and its port (Studio) or MySQL port (Local).
SOURCE=""
REG_NAME=""
REG_PORT=""
MYSQL_PORT=""
while IFS="$SEP" read -r source name root port _domain mysql; do
	if [ "$root" = "$ROOT" ]; then
		SOURCE="$source" REG_NAME="$name" REG_PORT="$port" MYSQL_PORT="$mysql"
		break
	fi
done < <(registry)

DB_DROPIN="$ROOT/wp-content/db.php"
if [ -z "$SOURCE" ]; then
	# Not registered: a SQLite site (e.g. a Studio site from another machine) is still fine.
	grep -qi sqlite "$DB_DROPIN" 2>/dev/null ||
		sbx_die "$ROOT is not in the Studio or Local registry and isn't a SQLite site; can't tell how to migrate it"
	SOURCE=studio
fi
if [ "$SOURCE" = studio ] && ! grep -qi sqlite "$DB_DROPIN" 2>/dev/null; then
	sbx_die "$ROOT has no SQLite drop-in (wp-content/db.php); not a Studio site"
fi

[ -n "$NAME" ] || NAME="$(sbx_slug "${REG_NAME:-$(basename "$ROOT")}")"
if [ "$SOURCE" = local ] && [ "$(basename "$ROOT")" = public ] && [ -z "$REG_NAME" ]; then
	NAME="$(sbx_slug "$(basename "$(dirname "$(dirname "$ROOT")")")")"
fi

if [ -z "$PORT" ]; then
	PORT="${REG_PORT:-}"
	[ -n "$PORT" ] || PORT="$(sbx_free_port "$SBX_DEFAULT_PORT")" || sbx_die "no free port found"
fi
# Studio serving the site would write to the same database while we change it.
if sbx_port_in_use "$PORT"; then
	sbx_die "port $PORT is in use: stop the site in Studio (or whatever uses the port) first, or pass --port"
fi
URL="http://localhost:$PORT"

sbx_has wp || sbx_die "WP-CLI is required (https://wp-cli.org/#installing)"
sbx_php_ok || sbx_die "PHP >= 8.1 is required"
wpcli() { wp --path="$ROOT" --skip-plugins --skip-themes "$@"; }

# wp-config.php values, read without loading WordPress.
wpconfig_value() {
	# shellcheck disable=SC2016 # PHP code, not shell
	php -r '
		$c = file_get_contents($argv[1]);
		if ($argv[2] === "table_prefix") {
			preg_match("/\\\$table_prefix\s*=\s*[\x27\"]([^\x27\"]+)[\x27\"]/", $c, $m);
		} else {
			preg_match("/define\s*\(\s*[\x27\"]" . preg_quote($argv[2], "/") . "[\x27\"]\s*,\s*[\x27\"]([^\x27\"]*)[\x27\"]/", $c, $m);
		}
		echo $m[1] ?? "";
	' "$ROOT/wp-config.php" "$1"
}
PREFIX="$(wpconfig_value table_prefix)"
printf '%s' "$PREFIX" | grep -qE '^[A-Za-z0-9_]+$' || sbx_die "could not read a valid \$table_prefix from wp-config.php"

if [ "$SOURCE" = local ] && [ -z "$MYSQL_PORT" ]; then
	sbx_die "Local's registry has no MySQL port for this site; start it in Local and try again"
fi

# 1. Backup: wp-config.php plus the database (SQLite file or MySQL dump).
BACKUP="$ROOT/.closehub-sandbox-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
chmod 700 "$BACKUP"
cp -p "$ROOT/wp-config.php" "$BACKUP/"
if [ "$SOURCE" = studio ]; then
	[ -d "$ROOT/wp-content/database" ] && cp -Rp "$ROOT/wp-content/database" "$BACKUP/database"
else
	sbx_info "dumping the Local MySQL database (port $MYSQL_PORT)"
	CLOSEHUB_SANDBOX_DB_PASSWORD="$(wpconfig_value DB_PASSWORD)" php "$SBX_ROOT/scripts/mysql-dump.php" \
		--host 127.0.0.1 --port "$MYSQL_PORT" --user "$(wpconfig_value DB_USER)" \
		--database "$(wpconfig_value DB_NAME)" --prefix "$PREFIX" --out "$BACKUP/database.sql" ||
		sbx_die "could not dump the database: start the site in Local and try again (backup left in $BACKUP)"
	# Another db.php drop-in (Query Monitor, W3TC...) would replace the SQLite one.
	if [ -f "$DB_DROPIN" ]; then
		mv "$DB_DROPIN" "$BACKUP/db.php"
		sbx_warn "moved the existing wp-content/db.php drop-in to the backup"
	fi
	sbx_info "installing the SQLite drop-in"
	sbx_install_sqlite "$ROOT"
fi
sbx_info "backup in $BACKUP"

# 2. Sandbox config: .env, the .env loader required from wp-config.php, server helpers.
ENV_FILE="$ROOT/.env"
[ ! -e "$ENV_FILE" ] || mv "$ENV_FILE" "$BACKUP/env.original"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_NAME "$NAME"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_BACKEND php
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_TYPE none
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_PROJECT "$ROOT"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_PORT "$PORT"
sbx_env_set "$ENV_FILE" WP_HOME "$URL"
sbx_env_set "$ENV_FILE" WP_SITEURL "$URL"
sbx_env_set "$ENV_FILE" WP_ENVIRONMENT_TYPE local
sbx_env_set "$ENV_FILE" WP_DEBUG true
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_USER "${CLOSEHUB_SANDBOX_ADMIN_USER:-admin}"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_PASSWORD "${CLOSEHUB_SANDBOX_ADMIN_PASSWORD:-password}"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_MIGRATED_FROM "$SOURCE"

cp "$SBX_ROOT/templates/wp-config-env.php" "$ROOT/closehub-sandbox-env.php"
# Require the loader right before wp-settings.php (after the site's own defines, so nothing is
# defined twice) and comment out URL constants that would override the new local URL.
# shellcheck disable=SC2016 # PHP code, not shell
php -r '
	$file = $argv[1];
	$c    = file_get_contents($file);
	$c    = preg_replace("/^(\s*define\s*\(\s*[\x27\"](WP_HOME|WP_SITEURL)[\x27\"].*)$/m", "// closehub-sandbox: $1", $c);
	if (false === strpos($c, "closehub-sandbox-env.php")) {
		$re = "/^(.*require(_once)?\s*\(?\s*ABSPATH\s*\.\s*[\x27\"]wp-settings\.php[\x27\"].*)$/m";
		if (!preg_match($re, $c)) { fwrite(STDERR, "wp-settings.php require not found in wp-config.php\n"); exit(1); }
		$c = preg_replace($re, "require_once __DIR__ . \x27/closehub-sandbox-env.php\x27;\n$1", $c, 1);
	}
	file_put_contents($file, $c);
' "$ROOT/wp-config.php" || sbx_die "could not update wp-config.php (backup in $BACKUP)"

mkdir -p "$ROOT/.closehub-sandbox-bin"
cp "$SBX_ROOT/scripts/serve.sh" "$SBX_ROOT/scripts/lib.sh" "$SBX_ROOT/scripts/router.php" "$ROOT/.closehub-sandbox-bin/"
chmod +x "$ROOT/.closehub-sandbox-bin/serve.sh"
if [ -d "$ROOT/.git" ]; then
	for entry in .env .closehub-sandbox-bin/ .closehub-sandbox-backup-*/ wp-content/database/ wp-content/debug.log; do
		grep -qxF "$entry" "$ROOT/.gitignore" 2>/dev/null || printf '%s\n' "$entry" >>"$ROOT/.gitignore"
	done
fi

# 3. Local: import the MySQL dump into SQLite (same path as --from clones).
if [ "$SOURCE" = local ]; then
	sbx_info "importing into SQLite"
	wpcli config set table_prefix wp_ --quiet >&2
	wpcli core install --url="$URL" --title="$NAME" --admin_user=admin --admin_password=password \
		--admin_email=admin@example.test --skip-email --quiet >&2 || true
	wpcli eval-file "$SBX_ROOT/scripts/import-sql.php" "$BACKUP/database.sql" >&2 ||
		sbx_die "import failed; the original wp-config.php and dump are in $BACKUP"
	wpcli config set table_prefix "$PREFIX" --quiet >&2
fi

# 4. Old URLs (custom domain, Local's .local) → http://localhost:<port>.
# shellcheck disable=SC2016 # PHP code, not shell
OLD_URLS="$(wpcli eval '
	global $wpdb;
	foreach ( array( "siteurl", "home" ) as $o ) {
		echo $wpdb->get_var( $wpdb->prepare( "SELECT option_value FROM {$wpdb->options} WHERE option_name = %s", $o ) ), "\n";
	}
' 2>/dev/null | sort -u)"
replace_url() {
	local from="$1" host variant to
	host="$(printf '%s' "$from" | sed -E 's#^[a-z]+://##; s#/+$##')"
	[ -n "$host" ] && [ "$host" != "localhost:$PORT" ] || return 0
	for variant in "https://$host" "http://$host" "//$host"; do
		to="$URL"
		[ "${variant#//}" != "$variant" ] && to="//${URL#*://}"
		wpcli search-replace "$variant" "$to" --all-tables-with-prefix --quiet >&2 || sbx_warn "search-replace failed for $variant"
	done
	sbx_info "replaced $host with localhost:$PORT"
}
while IFS= read -r old; do
	[ -n "$old" ] && replace_url "$old"
done <<<"$OLD_URLS"

# 5. Standard local login.
ADMIN_USER="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_USER)"
ADMIN_PASSWORD="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_PASSWORD)"
if wpcli user get "$ADMIN_USER" --field=ID >/dev/null 2>&1; then
	wpcli user update "$ADMIN_USER" --user_pass="$ADMIN_PASSWORD" --skip-email --quiet >&2
	wpcli user set-role "$ADMIN_USER" administrator --quiet >&2
else
	wpcli user create "$ADMIN_USER" "closehub-sandbox-admin@example.test" --role=administrator \
		--user_pass="$ADMIN_PASSWORD" --quiet >&2
fi
wp --path="$ROOT" rewrite flush --quiet >&2 2>/dev/null || wpcli rewrite flush --quiet >&2 || true

# 6. launch.json in the site itself: open Claude there and preview_start the entry.
LAUNCH_NAME="$(bash "$SBX_ROOT/scripts/launch.sh" --project "$ROOT" --site "$ROOT")"

sbx_info "migrated '$NAME' ($SOURCE) at $ROOT"
printf 'CLOSEHUB_SANDBOX_SITE=%s\n' "$ROOT"
printf 'CLOSEHUB_SANDBOX_NAME=%s\n' "$NAME"
printf 'CLOSEHUB_SANDBOX_SOURCE_APP=%s\n' "$SOURCE"
printf 'CLOSEHUB_SANDBOX_PORT=%s\n' "$PORT"
printf 'CLOSEHUB_SANDBOX_URL=%s\n' "$URL"
printf 'CLOSEHUB_SANDBOX_LAUNCH=%s\n' "$LAUNCH_NAME"
printf 'CLOSEHUB_SANDBOX_BACKUP=%s\n' "$BACKUP"
