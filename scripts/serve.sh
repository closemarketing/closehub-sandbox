#!/usr/bin/env bash
# Start the server of a sandbox. This is what .claude/launch.json runs.
# setup.sh copies this file (with lib.sh and router.php) into <site>/.closehub-sandbox-bin/.
#
# Usage: serve.sh [SITE_DIR]   (defaults to the site that contains this script)
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$BIN_DIR/lib.sh"

SITE="${1:-$(dirname "$BIN_DIR")}"
[ -d "$SITE" ] || sbx_die "site directory not found: $SITE"
SITE="$(cd "$SITE" && pwd)"
ENV_FILE="$SITE/.env"
sbx_env_load "$ENV_FILE" || sbx_die "missing $ENV_FILE; run setup.sh first"

PORT="${CLOSEHUB_SANDBOX_PORT:?CLOSEHUB_SANDBOX_PORT missing in $ENV_FILE}"
BACKEND="${CLOSEHUB_SANDBOX_BACKEND:-php}"

if sbx_port_in_use "$PORT"; then
	sbx_die "port $PORT is already in use; stop the other server or change CLOSEHUB_SANDBOX_PORT (and launch.json)"
fi

case "$BACKEND" in
php)
	sbx_php_ok || sbx_die "PHP >= $SBX_MIN_PHP is required"
	ROUTER="$BIN_DIR/router.php"
	[ -f "$ROUTER" ] || sbx_die "router not found: $ROUTER"
	# Several workers so WordPress loopback requests (site health, cron) don't deadlock.
	export PHP_CLI_SERVER_WORKERS="${PHP_CLI_SERVER_WORKERS:-4}"
	sbx_info "serving $SITE on http://localhost:$PORT"
	cd "$SITE"
	exec php -S "127.0.0.1:$PORT" -t "$SITE" "$ROUTER"
	;;
playground)
	sbx_has npx || sbx_die "Node.js (npx) is required for the playground backend"
	VERSION="${CLOSEHUB_SANDBOX_PLAYGROUND_VERSION:-latest}"
	# --auto-mount mounts the cwd as plugin/theme; only do it when the project is one.
	if [ "${CLOSEHUB_SANDBOX_TYPE:-none}" = none ]; then
		set -- --port="$PORT" --login
		cd "$SITE"
	else
		set -- --port="$PORT" --auto-mount --login
		cd "${CLOSEHUB_SANDBOX_PROJECT:?CLOSEHUB_SANDBOX_PROJECT missing in $ENV_FILE}"
	fi
	sbx_info "serving with WordPress Playground on http://localhost:$PORT"
	exec npx -y "@wp-playground/cli@$VERSION" server "$@"
	;;
*) sbx_die "unknown backend in $ENV_FILE: $BACKEND" ;;
esac
