#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	SITE="$CLOSEHUB_SANDBOX_HOME/clone"
	mkdir -p "$SITE"
	printf 'CLOSEHUB_SANDBOX_NAME=clone\nCLOSEHUB_SANDBOX_BACKEND=php\nWP_HOME=http://localhost:8099\n' >"$SITE/.env"
	echo '<?php' >"$SITE/wp-config.php"
	MANIFEST="$TEST_TMP/manifest.json"
	echo '{"prefix":"shop_","siteurl":"https://shop.example.com","home":"https://shop.example.com","plugins":[],"themes":[]}' >"$MANIFEST"
	export CLOSEHUB_EXPORT_TICKET="$(printf 'a%.0s' {1..64})"
}

teardown() { common_teardown; }

IMPORT() { bash "$SBX_REPO/scripts/import.sh" "$@"; }
ARGS() { echo --site "$SITE" --manifest "$MANIFEST" --job 0123456789abcdef --tables wp_posts "$@"; }

@test "requires the ticket in the environment" {
	unset CLOSEHUB_EXPORT_TICKET
	run IMPORT $(ARGS --base-url https://shop.example.com/wp-json/closehub-export/v1/db)
	[ "$status" -ne 0 ]
	[[ "$output" == *"CLOSEHUB_EXPORT_TICKET"* ]]
}

@test "refuses a plain HTTP export URL on a public host" {
	run IMPORT $(ARGS --base-url http://shop.example.com/wp-json/closehub-export/v1/db)
	[ "$status" -ne 0 ]
	[[ "$output" == *"non-HTTPS"* ]]
}

@test "refuses a directory that is not a sandbox" {
	printf 'APP_NAME=Laravel\n' >"$SITE/.env"
	run IMPORT $(ARGS --base-url https://shop.example.com/x)
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a closehub-sandbox site"* ]]
}

@test "refuses the playground backend" {
	printf 'CLOSEHUB_SANDBOX_NAME=clone\nCLOSEHUB_SANDBOX_BACKEND=playground\n' >"$SITE/.env"
	run IMPORT $(ARGS --base-url https://shop.example.com/x)
	[ "$status" -ne 0 ]
	[[ "$output" == *"php backend"* ]]
}

@test "rejects an invalid table prefix in the manifest" {
	command -v php >/dev/null && command -v wp >/dev/null && command -v curl >/dev/null || skip "needs php, wp and curl"
	echo '{"prefix":"x; DROP","siteurl":"https://a.test"}' >"$MANIFEST"
	run IMPORT $(ARGS --base-url https://shop.example.com/x)
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid table prefix"* ]]
}

@test "never puts the ticket on a command line" {
	! grep -nE 'curl[^|]*\$CLOSEHUB_EXPORT_TICKET' "$SBX_REPO/scripts/import.sh"
	grep -q -- '--config -' "$SBX_REPO/scripts/import.sh"
}
