#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	# shellcheck source=../scripts/lib.sh
	. "$SBX_REPO/scripts/lib.sh"
}

teardown() { common_teardown; }

@test "sbx_slug normalises names" {
	[ "$(sbx_slug 'My Plugin_v2!!')" = "my-plugin-v2" ]
	[ "$(sbx_slug '--Close--Theme--')" = "close-theme" ]
}

@test "sbx_home defaults to ~/SandBox and honours SANDBOXWP_HOME" {
	[ "$(sbx_home)" = "$TEST_TMP/SandBox" ]
	unset SANDBOXWP_HOME
	[ "$(sbx_home)" = "$HOME/SandBox" ]
}

@test "sbx_detect_type: plugin" {
	make_plugin "$PROJECT"
	[ "$(sbx_detect_type "$PROJECT")" = plugin ]
}

@test "sbx_detect_type: theme" {
	make_theme "$PROJECT"
	[ "$(sbx_detect_type "$PROJECT")" = theme ]
}

@test "sbx_detect_type: none" {
	echo '<?php echo 1;' >"$PROJECT/index.php"
	[ "$(sbx_detect_type "$PROJECT")" = none ]
}

@test "sbx_detect_type: ambiguous when plugin and theme headers coexist" {
	make_plugin "$PROJECT"
	make_theme "$PROJECT"
	[ "$(sbx_detect_type "$PROJECT")" = ambiguous ]
}

@test "sbx_env_set writes, replaces and keeps the file private" {
	f="$TEST_TMP/.env"
	sbx_env_set "$f" FOO one
	sbx_env_set "$f" BAR two
	sbx_env_set "$f" FOO three
	[ "$(sbx_env_get "$f" FOO)" = three ]
	[ "$(sbx_env_get "$f" BAR)" = two ]
	[ "$(grep -c '^FOO=' "$f")" -eq 1 ]
	perms="$(ls -l "$f" | cut -c1-10)"
	[ "$perms" = "-rw-------" ]
}

@test "sbx_env_get keeps '=' inside values" {
	f="$TEST_TMP/.env"
	sbx_env_set "$f" URL 'http://x/?a=b'
	[ "$(sbx_env_get "$f" URL)" = 'http://x/?a=b' ]
}

@test "sbx_env_load exports keys and skips comments and invalid keys" {
	f="$TEST_TMP/.env"
	printf '# comment\nSBX_A=1\nbad-key=2\n\nSBX_B=x=y\n' >"$f"
	sbx_env_load "$f"
	[ "$SBX_A" = 1 ]
	[ "$SBX_B" = "x=y" ]
}

@test "sbx_free_port returns a numeric port at or above the start" {
	port="$(sbx_free_port 18080)"
	[[ "$port" =~ ^[0-9]+$ ]]
	[ "$port" -ge 18080 ]
}
