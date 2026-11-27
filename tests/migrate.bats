#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	command -v php >/dev/null || skip "php not installed"
	STUDIO_SITE="$TEST_TMP/Studio/my-shop"
	mkdir -p "$STUDIO_SITE/wp-content/database"
	cat >"$STUDIO_SITE/wp-config.php" <<'PHP'
<?php
define( 'DB_NAME', 'wordpress' );
define( 'WP_HOME', 'http://my-shop.wp.local' );
define( 'WP_DEBUG', false );
$table_prefix = 'abc_';
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
PHP
	echo '<?php // SQLite integration (Drop-in)' >"$STUDIO_SITE/wp-content/db.php"
	echo sqlite >"$STUDIO_SITE/wp-content/database/.ht.sqlite"
	LOCAL_SITE="$TEST_TMP/Local Sites/old-blog"
	mkdir -p "$LOCAL_SITE/app/public"

	export CLOSEHUB_SANDBOX_STUDIO_CONFIG="$TEST_TMP/cli.json"
	export CLOSEHUB_SANDBOX_LOCAL_CONFIG="$TEST_TMP/sites.json"
	printf '{"sites":[{"name":"My Shop","path":"%s","port":8961,"customDomain":"my-shop.wp.local"},{"name":"Gone","path":"%s/Studio/gone","port":8962}]}' \
		"$STUDIO_SITE" "$TEST_TMP" >"$CLOSEHUB_SANDBOX_STUDIO_CONFIG"
	printf '{"x1":{"name":"Old Blog","path":"%s","domain":"old-blog.local","services":{"mysql":{"ports":{"MYSQL":[10011]}}}}}' \
		"$LOCAL_SITE" >"$CLOSEHUB_SANDBOX_LOCAL_CONFIG"

	# Fake WP-CLI: logs every call; the options query answers with the Studio custom domain.
	WP_LOG="$TEST_TMP/wp.log"
	export WP_LOG
	STUBS="$(stub_cmd wp 'echo "$*" >>"$WP_LOG"; case "$*" in *"eval "*) echo "http://my-shop.wp.local";; *"user get"*) exit 1;; esac; exit 0')"
}

teardown() { common_teardown; }

MIGRATE() { env PATH="$STUBS:$PATH" bash "$SBX_REPO/scripts/migrate.sh" "$@"; }

@test "--list shows Studio and Local sites with their status, keeping empty fields" {
	run MIGRATE --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"studio	My Shop	$STUDIO_SITE	8961	my-shop.wp.local	ready"* ]]
	[[ "$output" == *"studio	Gone	$TEST_TMP/Studio/gone	8962		missing"* ]]
	[[ "$output" == *"local	Old Blog	$LOCAL_SITE/app/public		old-blog.local	ready"* ]]
}

@test "migrates a Studio site in place: backup, .env, loader, URL replacement, login, launch.json" {
	run MIGRATE --site "$STUDIO_SITE"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CLOSEHUB_SANDBOX_URL=http://localhost:8961"* ]]
	[[ "$output" == *"CLOSEHUB_SANDBOX_SOURCE_APP=studio"* ]]

	backup="$(ls -d "$STUDIO_SITE"/.closehub-sandbox-backup-*)"
	grep -q "WP_HOME', 'http://my-shop.wp.local'" "$backup/wp-config.php"
	[ -f "$backup/database/.ht.sqlite" ]

	grep -qx 'CLOSEHUB_SANDBOX_NAME=my-shop' "$STUDIO_SITE/.env"
	grep -qx 'WP_HOME=http://localhost:8961' "$STUDIO_SITE/.env"
	grep -qx 'CLOSEHUB_SANDBOX_MIGRATED_FROM=studio' "$STUDIO_SITE/.env"

	# Loader required once, right before wp-settings.php; the old URL constant is commented out.
	[ "$(grep -c 'closehub-sandbox-env.php' "$STUDIO_SITE/wp-config.php")" -eq 1 ]
	grep -B1 "require_once ABSPATH . 'wp-settings.php'" "$STUDIO_SITE/wp-config.php" | grep -q closehub-sandbox-env.php
	grep -q "^// closehub-sandbox: define( 'WP_HOME'" "$STUDIO_SITE/wp-config.php"
	[ -f "$STUDIO_SITE/closehub-sandbox-env.php" ]
	[ -x "$STUDIO_SITE/.closehub-sandbox-bin/serve.sh" ]

	grep -q 'search-replace http://my-shop.wp.local http://localhost:8961' "$WP_LOG"
	grep -q 'search-replace https://my-shop.wp.local http://localhost:8961' "$WP_LOG"
	grep -q 'search-replace //my-shop.wp.local //localhost:8961' "$WP_LOG"
	grep -q 'user create admin' "$WP_LOG"
	grep -q '"closehub-sandbox-my-shop"' "$STUDIO_SITE/.claude/launch.json"
}

@test "a migrated site is left alone and listed as migrated" {
	MIGRATE --site "$STUDIO_SITE" >/dev/null 2>&1
	: >"$WP_LOG"
	run MIGRATE --site "$STUDIO_SITE"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already a closehub-sandbox site"* ]]
	[ ! -s "$WP_LOG" ]
	run MIGRATE --list
	[[ "$output" == *"my-shop.wp.local	migrated"* ]]
}

@test "refuses while the site's port is in use (still running in Studio)" {
	command -v nc >/dev/null || skip "nc not installed"
	nc -l 127.0.0.1 8961 >/dev/null 2>&1 &
	pid=$!
	sleep 0.5
	run MIGRATE --site "$STUDIO_SITE"
	kill "$pid" 2>/dev/null || true
	[ "$status" -ne 0 ]
	[[ "$output" == *"port 8961 is in use"* ]]
	[ ! -f "$STUDIO_SITE/.env" ]
}

@test "refuses a MySQL site that is in no registry" {
	other="$TEST_TMP/other"
	mkdir -p "$other"
	echo '<?php' >"$other/wp-config.php"
	run MIGRATE --site "$other"
	[ "$status" -ne 0 ]
	[[ "$output" == *"isn't a SQLite site"* ]]
}

@test "a Local site without a MySQL port fails before touching anything" {
	printf '{"x1":{"name":"Old Blog","path":"%s"}}' "$LOCAL_SITE" >"$CLOSEHUB_SANDBOX_LOCAL_CONFIG"
	printf '<?php\n$table_prefix = %s;\nrequire_once ABSPATH . %s;\n' "'wp_'" "'wp-settings.php'" >"$LOCAL_SITE/app/public/wp-config.php"
	run MIGRATE --site "$LOCAL_SITE" --port 8963
	[ "$status" -ne 0 ]
	[[ "$output" == *"no MySQL port"* ]]
	[ -z "$(ls -d "$LOCAL_SITE"/app/public/.closehub-sandbox-backup-* 2>/dev/null)" ]
}

@test "mysql-dump.php needs its arguments" {
	run php "$SBX_REPO/scripts/mysql-dump.php" --database x
	[ "$status" -eq 2 ]
	[[ "$output" == *"--user is required"* ]]
}

@test "--list follows Studio's movedTo to its new config file, without duplicates" {
	mv "$CLOSEHUB_SANDBOX_STUDIO_CONFIG" "$TEST_TMP/config.json"
	echo '{"version":2,"movedTo":"config.json"}' >"$CLOSEHUB_SANDBOX_STUDIO_CONFIG"
	CLOSEHUB_SANDBOX_STUDIO_CONFIG="$TEST_TMP/config.json,$CLOSEHUB_SANDBOX_STUDIO_CONFIG" run MIGRATE --list
	[ "$status" -eq 0 ]
	[ "$(grep -c 'My Shop' <<<"$output")" -eq 1 ]
	CLOSEHUB_SANDBOX_STUDIO_CONFIG="$TEST_TMP/cli.json" run MIGRATE --list
	[[ "$output" == *"studio	My Shop	$STUDIO_SITE	8961"* ]]
}
