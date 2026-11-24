#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	SITE="$CLOSEHUB_SANDBOX_HOME/demo"
	mkdir -p "$SITE/wp-content/plugins" "$SITE/.closehub-sandbox-bin"
	printf 'CLOSEHUB_SANDBOX_NAME=demo\nCLOSEHUB_SANDBOX_PORT=18777\n' >"$SITE/.env"
	echo '<?php' >"$SITE/wp-load.php"
}

teardown() { common_teardown; }

REMOVE() { bash "$SBX_REPO/scripts/remove.sh" "$@"; }

@test "refuses without --yes" {
	run REMOVE --site "$SITE"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--yes"* ]]
	[ -d "$SITE" ]
}

@test "refuses a directory that is not a sandbox" {
	other="$TEST_TMP/not-a-sandbox"
	mkdir -p "$other"
	printf 'APP_NAME=Laravel\n' >"$other/.env"
	run REMOVE --site "$other" --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a closehub-sandbox site"* ]]
	[ -d "$other" ]
}

@test "deletes the site and its launch.json entry" {
	bash "$SBX_REPO/scripts/launch.sh" --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	run REMOVE --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -eq 0 ]
	[ ! -e "$SITE" ]
	! grep -q closehub-sandbox-demo "$PROJECT/.claude/launch.json"
}

@test "never touches a mounted plugin repo" {
	make_plugin "$PROJECT"
	echo 'work in progress' >"$PROJECT/uncommitted.txt"
	ln -s "$PROJECT" "$SITE/wp-content/plugins/project"
	run REMOVE --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -eq 0 ]
	[ ! -e "$SITE" ]
	[ -f "$PROJECT/demo.php" ]
	[ -f "$PROJECT/uncommitted.txt" ]
}

@test "--keep-project-files keeps .claude, .git and docs" {
	mkdir -p "$SITE/.claude" "$SITE/.git"
	echo '# site' >"$SITE/AGENTS.md"
	run REMOVE --site "$SITE" --project "$SITE" --keep-project-files --yes
	[ "$status" -eq 0 ]
	[ -d "$SITE/.claude" ]
	[ -d "$SITE/.git" ]
	[ -f "$SITE/AGENTS.md" ]
	[ ! -e "$SITE/.env" ]
	[ ! -e "$SITE/wp-load.php" ]
	[ ! -e "$SITE/wp-content" ]
	[ ! -e "$SITE/.closehub-sandbox-bin" ]
}

@test "stops a server still listening on the sandbox port" {
	command -v php >/dev/null || skip "php not installed"
	docroot="$TEST_TMP/docroot"
	mkdir -p "$docroot"
	php -S 127.0.0.1:18777 -t "$docroot" >/dev/null 2>&1 &
	for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s http://127.0.0.1:18777/ >/dev/null && break; sleep 0.2; done
	run REMOVE --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -eq 0 ]
	sleep 0.5
	! curl -s -o /dev/null http://127.0.0.1:18777/
}
