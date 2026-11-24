# Shared bats helpers.

SBX_REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

common_setup() {
	TEST_TMP="$(mktemp -d)"
	export CLOSEHUB_SANDBOX_HOME="$TEST_TMP/SandBox"
	PROJECT="$TEST_TMP/project"
	mkdir -p "$PROJECT"
}

common_teardown() {
	rm -rf "$TEST_TMP"
}

make_plugin() {
	printf '<?php\n/**\n * Plugin Name: Demo\n */\n' >"$1/demo.php"
}

make_theme() {
	printf '/*\nTheme Name: Demo\n*/\n' >"$1/style.css"
}

# PATH with only basic tools: no php, wp, npx, node. Lets tests simulate missing dependencies.
minimal_path() {
	local bin="$TEST_TMP/minbin" tool src
	mkdir -p "$bin"
	for tool in bash sh env cat cp mv rm mkdir mktemp chmod dirname basename sed grep tr head tail cut printf pwd ln; do
		src="$(command -v "$tool" || true)"
		[ -n "$src" ] && [ -x "$src" ] && ln -sf "$src" "$bin/$tool"
	done
	printf '%s\n' "$bin"
}

# Directory with fake executables, prepended to PATH. Usage: stub_cmd NAME 'script body'
stub_cmd() {
	local dir="$TEST_TMP/stubs"
	mkdir -p "$dir"
	printf '#!/usr/bin/env bash\n%s\n' "$2" >"$dir/$1"
	chmod +x "$dir/$1"
	printf '%s\n' "$dir"
}
