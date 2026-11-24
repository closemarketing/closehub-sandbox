#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	SITE="$SANDBOXWP_HOME/demo"
	mkdir -p "$SITE"
	printf 'SANDBOXWP_NAME=demo\nSANDBOXWP_PORT=8123\n' >"$SITE/.env"
}

teardown() { common_teardown; }

LAUNCH() { bash "$SBX_REPO/scripts/launch.sh" "$@"; }

json_get() {
	php -r '$d = json_decode(file_get_contents($argv[1]), true); echo json_encode($d["configurations"], JSON_UNESCAPED_SLASHES);' "$1"
}

@test "creates launch.json when missing and prints the configuration name" {
	run LAUNCH --project "$PROJECT" --site "$SITE"
	[ "$status" -eq 0 ]
	[ "${lines[${#lines[@]}-1]}" = "sandboxwp-demo" ]
	f="$PROJECT/.claude/launch.json"
	[ -f "$f" ]
	run json_get "$f"
	[[ "$output" == *'"name":"sandboxwp-demo"'* ]]
	[[ "$output" == *'"runtimeExecutable":"bash"'* ]]
	[[ "$output" == *"\"port\":8123"* ]]
	[[ "$output" == *"$SITE/.sandboxwp-bin/serve.sh"* ]]
}

@test "keeps other configurations and does not duplicate its own" {
	mkdir -p "$PROJECT/.claude"
	echo '{"version":"0.0.1","configurations":[{"name":"vite","port":5173}]}' >"$PROJECT/.claude/launch.json"
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	LAUNCH --project "$PROJECT" --site "$SITE" >/dev/null 2>&1
	run json_get "$PROJECT/.claude/launch.json"
	[[ "$output" == *'"name":"vite"'* ]]
	[ "$(grep -o 'sandboxwp-demo' <<<"$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "fails when the site has no .env" {
	run LAUNCH --project "$PROJECT" --site "$TEST_TMP"
	[ "$status" -ne 0 ]
	[[ "$output" == *"run setup.sh first"* ]]
}
