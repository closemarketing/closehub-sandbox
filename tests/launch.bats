#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	SITE="$CLOSEHUB_SANDBOX_HOME/demo"
	mkdir -p "$SITE"
	printf 'CLOSEHUB_SANDBOX_NAME=demo\nCLOSEHUB_SANDBOX_PORT=8123\n' >"$SITE/.env"
}

teardown() { common_teardown; }

LAUNCH() { bash "$SBX_REPO/scripts/launch.sh" "$@"; }

json_get() {
	php -r '$d = json_decode(file_get_contents($argv[1]), true); echo json_encode($d["configurations"], JSON_UNESCAPED_SLASHES);' "$1"
}

@test "creates launch.json when missing and prints the configuration name" {
	run LAUNCH --project "$PROJECT" --site "$SITE"
	[ "$status" -eq 0 ]
	[ "${lines[${#lines[@]}-1]}" = "closehub-sandbox-demo" ]
	f="$PROJECT/.claude/launch.json"
	[ -f "$f" ]
	run json_get "$f"
	[[ "$output" == *'"name":"closehub-sandbox-demo"'* ]]
	[[ "$output" == *'"runtimeExecutable":"bash"'* ]]
	[[ "$output" == *"\"port\":8123"* ]]
	[[ "$output" == *"$SITE/.closehub-sandbox-bin/serve.sh"* ]]
}

@test "keeps other configurations and does not duplicate its own" {
	mkdir -p "$PROJECT/.claude"
	echo '{"version":"0.0.1","configurations":[{"name":"vite","port":5173}]}' >"$PROJECT/.claude/launch.json"
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	run json_get "$PROJECT/.claude/launch.json"
	[[ "$output" == *'"name":"vite"'* ]]
	[ "$(grep -o 'closehub-sandbox-demo' <<<"$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "fails when the site has no .env" {
	run LAUNCH --project "$PROJECT" --site "$TEST_TMP"
	[ "$status" -ne 0 ]
	[[ "$output" == *"run setup.sh first"* ]]
}

@test "--list reports ok and missing sites" {
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	gone="$CLOSEHUB_SANDBOX_HOME/gone"
	mkdir -p "$gone"
	printf 'CLOSEHUB_SANDBOX_NAME=gone\nCLOSEHUB_SANDBOX_PORT=8124\n' >"$gone/.env"
	LAUNCH --project "$PROJECT" --site "$gone" >/dev/null 2>&1
	rm -rf "$gone"

	run LAUNCH --project "$PROJECT" --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"closehub-sandbox-demo	$SITE	ok"* ]]
	[[ "$output" == *"closehub-sandbox-gone	$gone	missing"* ]]
}

@test "--list ignores other configurations and a missing launch.json" {
	run LAUNCH --project "$PROJECT" --list
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	mkdir -p "$PROJECT/.claude"
	echo '{"version":"0.0.1","configurations":[{"name":"vite","port":5173}]}' >"$PROJECT/.claude/launch.json"
	run LAUNCH --project "$PROJECT" --list
	[ -z "$output" ]
}

@test "--remove drops only the named entry, even if the site is gone" {
	mkdir -p "$PROJECT/.claude"
	echo '{"version":"0.0.1","configurations":[{"name":"vite","port":5173}]}' >"$PROJECT/.claude/launch.json"
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	rm -rf "$SITE"

	run LAUNCH --project "$PROJECT" --remove closehub-sandbox-demo
	[ "$status" -eq 0 ]
	run json_get "$PROJECT/.claude/launch.json"
	[[ "$output" == *'"name":"vite"'* ]]
	[[ "$output" != *"closehub-sandbox-demo"* ]]
}
