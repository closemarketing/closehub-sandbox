#!/usr/bin/env bats

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

SETUP() { bash "$SBX_REPO/scripts/setup.sh" "$@"; }

@test "rejects unknown arguments" {
	run SETUP --nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown argument"* ]]
}

@test "rejects an invalid --type" {
	run SETUP --project "$PROJECT" --type banana
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid --type"* ]]
}

@test "asks for --type when the project is both plugin and theme" {
	make_plugin "$PROJECT"
	make_theme "$PROJECT"
	run SETUP --project "$PROJECT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--type plugin|theme"* ]]
}

@test "explains what to install when no backend is available" {
	make_plugin "$PROJECT"
	PATH="$(minimal_path)" run SETUP --project "$PROJECT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"WP-CLI"* ]]
	[[ "$output" == *"Node.js"* ]]
}

@test "php backend fails clearly without WP-CLI" {
	PATH="$(minimal_path)" run SETUP --project "$PROJECT" --backend php
	[ "$status" -ne 0 ]
	[[ "$output" == *"PHP >="* ]]
}

@test "playground backend writes the site .env under SANDBOXWP_HOME without downloading WordPress" {
	make_theme "$PROJECT"
	stubs="$(stub_cmd npx 'exit 0')"
	PATH="$stubs:$(minimal_path)" run SETUP --project "$PROJECT" --name "My Theme" --backend playground --port 9123
	[ "$status" -eq 0 ]
	site="$SANDBOXWP_HOME/my-theme"
	[[ "$output" == *"SANDBOXWP_SITE=$site"* ]]
	[[ "$output" == *"SANDBOXWP_URL=http://localhost:9123"* ]]
	[ -f "$site/.env" ]
	grep -q '^SANDBOXWP_BACKEND=playground$' "$site/.env"
	grep -q '^SANDBOXWP_TYPE=theme$' "$site/.env"
	grep -q "^SANDBOXWP_PROJECT=$PROJECT\$" "$site/.env"
	[ -x "$site/.sandboxwp-bin/serve.sh" ]
	[ -f "$site/.sandboxwp-bin/router.php" ]
	[ ! -f "$site/wp-config.php" ]
}

@test "--type from AGENTS.md wins over header detection" {
	make_plugin "$PROJECT"
	stubs="$(stub_cmd npx 'exit 0')"
	PATH="$stubs:$(minimal_path)" run SETUP --project "$PROJECT" --type none --backend playground --port 9124
	[ "$status" -eq 0 ]
	grep -q '^SANDBOXWP_TYPE=none$' "$SANDBOXWP_HOME/project/.env"
}

@test "never prints the generated admin password" {
	stubs="$(stub_cmd npx 'exit 0')"
	PATH="$stubs:$(minimal_path)" run SETUP --project "$PROJECT" --backend playground --port 9125
	[ "$status" -eq 0 ]
	pw="$(grep '^SANDBOXWP_ADMIN_PASSWORD=' "$SANDBOXWP_HOME/project/.env" | cut -d= -f2)"
	[ -n "$pw" ]
	[[ "$output" != *"$pw"* ]]
}

@test "re-running reuses an existing sandbox" {
	stubs="$(stub_cmd npx 'exit 0')"
	PATH="$stubs:$(minimal_path)" run SETUP --project "$PROJECT" --backend playground --port 9126
	[ "$status" -eq 0 ]
	PATH="$stubs:$(minimal_path)" run SETUP --project "$PROJECT" --backend playground --port 9999
	[ "$status" -eq 0 ]
	[[ "$output" == *"already exists"* ]]
	[[ "$output" == *"SANDBOXWP_PORT=9126"* ]]
}
