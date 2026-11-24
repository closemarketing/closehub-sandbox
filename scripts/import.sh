#!/usr/bin/env bash
# Import a live site's database into an existing sandbox (php backend), from a
# closehub-connector-export job.
#
# Usage:
#   CLOSEHUB_EXPORT_TICKET=<ticket> import.sh --site SITE_DIR --manifest MANIFEST.json \
#     --base-url URL --job JOB_ID --tables "wp_options,wp_posts,..." [--limit 1000] [--keep-dump]
#
# MANIFEST.json is the output of the closehub-export/db-manifest ability. base_url, job_id, tables
# and the ticket come from closehub-export/create-db-export. The ticket is read from the
# environment and passed to curl on stdin, never on the command line.
#
# Steps: download chunks (resumable) → set table prefix → import through the SQLite driver →
# replace production URLs → same plugins/theme from WordPress.org → safety (no email, no outgoing
# HTTP, no WP-Cron) → admin / password login. The dump is deleted afterwards unless --keep-dump.
# Prints KEY=value lines (CLOSEHUB_SANDBOX_SOURCE, CLOSEHUB_SANDBOX_PENDING_PLUGINS, ...).
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

SITE="" MANIFEST="" BASE_URL="" JOB="" TABLES="" LIMIT=1000 KEEP_DUMP=0
while [ $# -gt 0 ]; do
	case "$1" in
	--site) SITE="${2:?}"; shift 2 ;;
	--manifest) MANIFEST="${2:?}"; shift 2 ;;
	--base-url) BASE_URL="${2:?}"; shift 2 ;;
	--job) JOB="${2:?}"; shift 2 ;;
	--tables) TABLES="${2:?}"; shift 2 ;;
	--limit) LIMIT="${2:?}"; shift 2 ;;
	--keep-dump) KEEP_DUMP=1; shift ;;
	-h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) sbx_die "unknown argument: $1 (see --help)" ;;
	esac
done

[ -n "$SITE" ] && [ -n "$MANIFEST" ] && [ -n "$BASE_URL" ] && [ -n "$JOB" ] && [ -n "$TABLES" ] ||
	sbx_die "missing arguments (see --help)"
[ -n "${CLOSEHUB_EXPORT_TICKET:-}" ] || sbx_die "set CLOSEHUB_EXPORT_TICKET"
[ -d "$SITE" ] || sbx_die "site directory not found: $SITE"
SITE="$(cd "$SITE" && pwd)"
ENV_FILE="$SITE/.env"
[ -n "$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_NAME 2>/dev/null || true)" ] || sbx_die "$SITE is not a closehub-sandbox site"
[ "$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_BACKEND)" = php ] || sbx_die "importing needs the php backend (Playground doesn't keep a database)"
[ -f "$SITE/wp-config.php" ] || sbx_die "$SITE has no wp-config.php; run setup.sh first"
[ -f "$MANIFEST" ] || sbx_die "manifest not found: $MANIFEST"
if ! sbx_php_ok || ! sbx_has wp || ! sbx_has curl; then
	sbx_die "need PHP >= $SBX_MIN_PHP, WP-CLI and curl"
fi

case "$BASE_URL" in
https://*) ;;
http://localhost[:/]* | http://127.0.0.1[:/]* | http://*.test[:/]* | http://*.localhost[:/]*) ;;
*) sbx_die "refusing a non-HTTPS export URL: $BASE_URL" ;;
esac
BASE_URL="${BASE_URL%/}"

# manifest field (dot path) or a TAB-separated plugin/theme list.
manifest() {
	# shellcheck disable=SC2016 # PHP code, not shell
	php -r '
	$m = json_decode(file_get_contents($argv[1]), true);
	if (!is_array($m)) { fwrite(STDERR, "invalid manifest\n"); exit(1); }
	switch ($argv[2]) {
		case "plugins": foreach ($m["plugins"] ?? [] as $p) { echo $p["slug"], "\t", $p["version"], "\t", empty($p["on_wporg"]) ? "0" : "1", "\n"; } break;
		case "themes":  foreach ($m["themes"] ?? [] as $t) { echo $t["slug"], "\t", $t["version"], "\t", empty($t["on_wporg"]) ? "0" : "1", "\t", $t["role"], "\n"; } break;
		default: echo $m[$argv[2]] ?? "";
	}' "$MANIFEST" "$1"
}

PREFIX="$(manifest prefix)"
SOURCE_URL="$(manifest siteurl)"
SOURCE_HOME="$(manifest home)"
[[ "$PREFIX" =~ ^[A-Za-z0-9_]+$ ]] || sbx_die "invalid table prefix in manifest: '$PREFIX'"
[ -n "$SOURCE_URL" ] || sbx_die "manifest has no siteurl"
LOCAL_URL="$(sbx_env_get "$ENV_FILE" WP_HOME)"

WORK="$SITE/.closehub-sandbox-import"
PARTS="$WORK/parts"
mkdir -p "$PARTS"
chmod 700 "$WORK"
cp "$MANIFEST" "$WORK/manifest.json" 2>/dev/null || true

wpcli() { wp --path="$SITE" --skip-plugins --skip-themes "$@"; }

# 1. Download. One file per chunk, cursor saved after each: re-running resumes without duplicates.
fetch() {
	local endpoint="$1" out="$2"
	shift 2
	printf 'header = "X-CloseHub-Export-Ticket: %s"\n' "$CLOSEHUB_EXPORT_TICKET" |
		curl --config - --silent --show-error --fail-with-body --location \
			--get "$BASE_URL/$endpoint" --data-urlencode "job=$JOB" "$@" \
			--dump-header "$PARTS/.headers" --output "$out" ||
		sbx_die "export request to $endpoint failed: $(head -c 300 "$out" 2>/dev/null)"
}
header_value() { grep -i "^$1:" "$PARTS/.headers" | tail -n 1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }

IFS=',' read -r -a TABLE_LIST <<<"$TABLES"
for table in "${TABLE_LIST[@]}"; do
	table="$(printf '%s' "$table" | tr -d '[:space:]')"
	[ -n "$table" ] || continue
	[[ "$table" =~ ^[A-Za-z0-9_\$]+$ ]] || sbx_die "invalid table name: $table"
	[ -f "$PARTS/$table.done" ] && continue
	if [ ! -s "$PARTS/$table.schema.sql" ]; then
		fetch schema "$PARTS/$table.schema.tmp" --data-urlencode "table=$table"
		mv "$PARTS/$table.schema.tmp" "$PARTS/$table.schema.sql"
	fi
	index=0 after=""
	[ -f "$PARTS/$table.cursor" ] && { read -r index after <"$PARTS/$table.cursor" || true; }
	while :; do
		chunk="$(printf '%s/%s.rows.%06d.sql' "$PARTS" "$table" "$index")"
		fetch rows "$chunk.tmp" --data-urlencode "table=$table" --data-urlencode "after=$after" --data-urlencode "limit=$LIMIT"
		mv "$chunk.tmp" "$chunk"
		after="$(header_value X-CloseHub-Next)"
		index=$((index + 1))
		printf '%s %s\n' "$index" "$after" >"$PARTS/$table.cursor"
		[ -n "$after" ] || break
	done
	touch "$PARTS/$table.done"
	sbx_info "downloaded $table"
done

DUMP="$WORK/dump.sql"
{
	for table in "${TABLE_LIST[@]}"; do
		table="$(printf '%s' "$table" | tr -d '[:space:]')"
		[ -n "$table" ] || continue
		cat "$PARTS/$table.schema.sql"
		for chunk in "$PARTS/$table".rows.*.sql; do
			[ -e "$chunk" ] && cat "$chunk"
		done
	done
} >"$DUMP"
rm -f "$PARTS/.headers"

# 2-3. Run every statement through the SQLite driver (the dump creates the production-prefixed
# tables), then switch to the production prefix. In this order WP-CLI can still boot the empty site.
sbx_info "importing into SQLite"
# Back to the prefix setup.sh installed with, so a re-run (or a run after a failed one) can boot WP.
wpcli config set table_prefix wp_ --quiet >&2
wpcli eval-file "$SBX_ROOT/scripts/import-sql.php" "$DUMP" >&2 || sbx_die "import failed (see warnings above); the dump is kept in $WORK"
wpcli config set table_prefix "$PREFIX" --quiet >&2

# 4. Production URLs → local, for every scheme variant.
replace_url() {
	local from="$1" host
	[ -n "$from" ] || return 0
	host="$(printf '%s' "$from" | sed -E 's#^[a-z]+://##; s#/+$##')"
	for variant in "https://$host" "http://$host" "//$host"; do
		local to="$LOCAL_URL"
		[ "${variant#//}" != "$variant" ] && to="//${LOCAL_URL#*://}"
		wpcli search-replace "$variant" "$to" --all-tables-with-prefix --quiet >&2 || sbx_warn "search-replace failed for $variant"
	done
}
replace_url "$SOURCE_URL"
[ "$SOURCE_HOME" != "$SOURCE_URL" ] && replace_url "$SOURCE_HOME"

# 5. Safety: no email, no outgoing HTTP except WordPress.org, no WP-Cron.
mkdir -p "$SITE/wp-content/mu-plugins"
cp "$SBX_ROOT/templates/closehub-sandbox-safety.php" "$SITE/wp-content/mu-plugins/"
sbx_env_set "$ENV_FILE" DISABLE_WP_CRON true

# 6. Same plugins and theme from WordPress.org; a mounted repo (symlink) always wins.
PENDING=""
while IFS="$(printf '\t')" read -r slug version on_wporg; do
	[ -n "$slug" ] || continue
	if [ -e "$SITE/wp-content/plugins/$slug" ]; then
		continue
	fi
	if [ "$on_wporg" = 1 ]; then
		wpcli plugin install "$slug" --version="$version" --quiet >&2 ||
			wpcli plugin install "$slug" --quiet >&2 ||
			PENDING="$PENDING $slug"
	else
		PENDING="$PENDING $slug"
	fi
done < <(manifest plugins)

PENDING_THEMES=""
while IFS="$(printf '\t')" read -r slug version on_wporg _role; do
	[ -n "$slug" ] || continue
	[ -e "$SITE/wp-content/themes/$slug" ] && continue
	if [ "$on_wporg" = 1 ]; then
		wpcli theme install "$slug" --version="$version" --quiet >&2 ||
			wpcli theme install "$slug" --quiet >&2 ||
			PENDING_THEMES="$PENDING_THEMES $slug"
	else
		PENDING_THEMES="$PENDING_THEMES $slug"
	fi
done < <(manifest themes)

# The repo this sandbox was created for stays active on top of the imported setup.
TYPE="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_TYPE)"
NAME="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_NAME)"
case "$TYPE" in
plugin) wp --path="$SITE" plugin activate "$NAME" --quiet >&2 || sbx_warn "could not activate plugin '$NAME'" ;;
theme) wp --path="$SITE" theme activate "$NAME" --quiet >&2 || sbx_warn "could not activate theme '$NAME'" ;;
esac

# 7. Fixed local login.
ADMIN_USER="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_USER)"
ADMIN_PASSWORD="$(sbx_env_get "$ENV_FILE" CLOSEHUB_SANDBOX_ADMIN_PASSWORD)"
if wpcli user get "$ADMIN_USER" --field=ID >/dev/null 2>&1; then
	wpcli user update "$ADMIN_USER" --user_pass="$ADMIN_PASSWORD" --skip-email --quiet >&2
	wpcli user set-role "$ADMIN_USER" administrator --quiet >&2
else
	wpcli user create "$ADMIN_USER" "closehub-sandbox-admin@example.test" --role=administrator \
		--user_pass="$ADMIN_PASSWORD" --quiet >&2
fi

wp --path="$SITE" rewrite flush --quiet >&2 2>/dev/null || wpcli rewrite flush --quiet >&2 || true

sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_SOURCE "$SOURCE_URL"
sbx_env_set "$ENV_FILE" CLOSEHUB_SANDBOX_IMPORTED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The dump holds production data: don't leave it around.
if [ "$KEEP_DUMP" = 1 ]; then
	sbx_info "dump kept in $WORK"
else
	rm -rf "$PARTS" "$DUMP"
fi

printf 'CLOSEHUB_SANDBOX_SOURCE=%s\n' "$SOURCE_URL"
printf 'CLOSEHUB_SANDBOX_URL=%s\n' "$LOCAL_URL"
printf 'CLOSEHUB_SANDBOX_PENDING_PLUGINS=%s\n' "$(printf '%s' "$PENDING" | sed 's/^ //')"
printf 'CLOSEHUB_SANDBOX_PENDING_THEMES=%s\n' "$(printf '%s' "$PENDING_THEMES" | sed 's/^ //')"
