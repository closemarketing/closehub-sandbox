#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	SITE="$SANDBOXWP_HOME/demo"
	mkdir -p "$SITE/.sandboxwp-bin"
	cp "$SBX_REPO/scripts/serve.sh" "$SBX_REPO/scripts/lib.sh" "$SBX_REPO/scripts/router.php" "$SITE/.sandboxwp-bin/"
}

teardown() { common_teardown; }

SERVE() { bash "$SITE/.sandboxwp-bin/serve.sh" "$@"; }

@test "fails without a site .env" {
	run SERVE
	[ "$status" -ne 0 ]
	[[ "$output" == *"run setup.sh first"* ]]
}

@test "rejects an unknown backend" {
	printf 'SANDBOXWP_PORT=18991\nSANDBOXWP_BACKEND=apache\n' >"$SITE/.env"
	run SERVE
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown backend"* ]]
}

@test "defaults the site to the directory that contains .sandboxwp-bin" {
	printf 'SANDBOXWP_PORT=18992\nSANDBOXWP_BACKEND=playground\nSANDBOXWP_TYPE=none\n' >"$SITE/.env"
	stubs="$(stub_cmd npx 'echo "npx $* in $PWD"')"
	PATH="$stubs:$(minimal_path)" run SERVE
	[ "$status" -eq 0 ]
	[[ "$output" == *"@wp-playground/cli@latest server --port=18992 --login"* ]]
	[[ "$output" == *"in $SITE"* ]]
	[[ "$output" != *"--auto-mount"* ]]
}

@test "playground mounts the project when it is a plugin or theme" {
	printf 'SANDBOXWP_PORT=18993\nSANDBOXWP_BACKEND=playground\nSANDBOXWP_TYPE=plugin\nSANDBOXWP_PROJECT=%s\n' "$PROJECT" >"$SITE/.env"
	stubs="$(stub_cmd npx 'echo "npx $* in $PWD"')"
	PATH="$stubs:$(minimal_path)" run SERVE
	[ "$status" -eq 0 ]
	[[ "$output" == *"--auto-mount"* ]]
	[[ "$output" == *"in $PROJECT"* ]]
}

@test "router blocks dotfiles and routes unknown paths to index.php" {
	command -v php >/dev/null || skip "php not installed"
	docroot="$TEST_TMP/docroot"
	mkdir -p "$docroot"
	echo '<?php echo "INDEX:" . $_SERVER["REQUEST_URI"];' >"$docroot/index.php"
	echo 'SECRET=1' >"$docroot/.env"
	port=18994
	php -S "127.0.0.1:$port" -t "$docroot" "$SBX_REPO/scripts/router.php" >/dev/null 2>&1 &
	pid=$!
	for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s "http://127.0.0.1:$port/" >/dev/null && break; sleep 0.2; done
	env_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/.env")"
	pretty="$(curl -s "http://127.0.0.1:$port/hello-world/")"
	kill "$pid"
	[ "$env_code" = 403 ]
	[ "$pretty" = "INDEX:/hello-world/" ]
}
