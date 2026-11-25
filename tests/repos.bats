#!/usr/bin/env bats

load helpers

setup() {
	common_setup
	command -v git >/dev/null || skip "git not installed"
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
	SITE="$CLOSEHUB_SANDBOX_HOME/site"
	mkdir -p "$SITE/wp-content/plugins" "$SITE/wp-content/themes"
	printf 'CLOSEHUB_SANDBOX_NAME=site\nCLOSEHUB_SANDBOX_PORT=8099\n' >"$SITE/.env"
	REMOTES="$TEST_TMP/remotes"
	mkdir -p "$REMOTES"
}

teardown() { common_teardown; }

# make_remote NAME [FILE CONTENT]...: a bare repository with one commit.
make_remote() {
	local name="$1" work="$TEST_TMP/work-$1"
	shift
	git init -q "$work"
	while [ $# -gt 1 ]; do
		printf '%s\n' "$2" >"$work/$1"
		shift 2
	done
	[ -n "$(ls -A "$work" | grep -v '^.git$')" ] || echo x >"$work/README.md"
	git -C "$work" add -A && git -C "$work" commit -qm init
	git clone -q --bare "$work" "$REMOTES/$name.git"
	printf 'file://%s\n' "$REMOTES/$name.git"
}

REPOS() { bash "$SBX_REPO/scripts/repos.sh" "$@"; }

@test "refuses a directory that is not a sandbox" {
	rm "$SITE/.env"
	run REPOS --site "$SITE" --plugin a/b
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a closehub-sandbox site"* ]]
}

@test "clones a plugin and a theme into their folders, not as symlinks" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	t="$(make_remote client-theme style.css '/* Theme Name: Client */')"
	run REPOS --site "$SITE" --plugin "$p" --theme "$t"
	[ "$status" -eq 0 ]
	[ -d "$SITE/wp-content/plugins/my-plugin/.git" ] && [ ! -L "$SITE/wp-content/plugins/my-plugin" ]
	[ -f "$SITE/wp-content/themes/client-theme/style.css" ]
	[[ "$output" == *"CLOSEHUB_SANDBOX_REPOS=plugin:my-plugin theme:client-theme"* ]]
}

@test "=slug chooses the folder name" {
	p="$(make_remote connect-repo plugin.php '<?php')"
	run REPOS --site "$SITE" --plugin "$p=connect-slug"
	[ "$status" -eq 0 ]
	[ -d "$SITE/wp-content/plugins/connect-slug/.git" ]
}

@test "leaves an existing checkout of the same repository alone" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	REPOS --site "$SITE" --plugin "$p" >/dev/null 2>&1
	echo local >"$SITE/wp-content/plugins/my-plugin/local.txt"
	run REPOS --site "$SITE" --plugin "$p"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already cloned"* ]]
	[ -f "$SITE/wp-content/plugins/my-plugin/local.txt" ]
}

@test "refuses to replace a folder that is not that repository, and keeps it" {
	p="$(make_remote woocommerce plugin.php '<?php')"
	mkdir -p "$SITE/wp-content/plugins/woocommerce"
	echo wporg >"$SITE/wp-content/plugins/woocommerce/woocommerce.php"
	run REPOS --site "$SITE" --plugin "$p"
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
	[ "$(cat "$SITE/wp-content/plugins/woocommerce/woocommerce.php")" = wporg ]
}

@test "reports composer install and npm build steps still to do" {
	p="$(make_remote dep-plugin composer.json '{}' package.json '{"scripts":{"build":"x"}}')"
	stubs="$(stub_cmd composer 'exit 1')"
	run env PATH="$stubs:$PATH" bash "$SBX_REPO/scripts/repos.sh" --site "$SITE" --plugin "$p"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CLOSEHUB_SANDBOX_REPOS_TODO=dep-plugin:composer-install dep-plugin:npm-build"* ]]
}

@test "a site under git ignores the cloned repositories" {
	git init -q "$SITE"
	t="$(make_remote client-theme style.css '/* Theme Name: Client */')"
	run REPOS --site "$SITE" --theme "$t"
	[ "$status" -eq 0 ]
	grep -qxF '/wp-content/themes/client-theme/' "$SITE/.gitignore"
}

@test "rejects an invalid repository" {
	run REPOS --site "$SITE" --plugin "not-a-repo"
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid repository"* ]]
}

@test "remove.sh stops on a cloned repository with uncommitted work" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	REPOS --site "$SITE" --plugin "$p" >/dev/null 2>&1
	echo change >>"$SITE/wp-content/plugins/my-plugin/plugin.php"
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"wp-content/plugins/my-plugin"* ]]
	[ -d "$SITE" ]
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes --discard-repo-changes
	[ "$status" -eq 0 ]
	[ ! -d "$SITE" ]
}

@test "remove.sh stops on unpushed commits and allows a clean, pushed checkout" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	REPOS --site "$SITE" --plugin "$p" >/dev/null 2>&1
	repo="$SITE/wp-content/plugins/my-plugin"
	echo change >>"$repo/plugin.php"
	git -C "$repo" commit -qam local
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -ne 0 ]
	git -C "$repo" push -q origin HEAD
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -eq 0 ]
	[ ! -d "$SITE" ]
}

@test "remove.sh stops on commits made from a detached HEAD" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	REPOS --site "$SITE" --plugin "$p" >/dev/null 2>&1
	repo="$SITE/wp-content/plugins/my-plugin"
	git -C "$repo" checkout -q --detach
	echo change >>"$repo/plugin.php"
	git -C "$repo" commit -qam detached
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -ne 0 ]
	[ -d "$repo" ]
}

@test "remove.sh stops on stashed work" {
	p="$(make_remote my-plugin plugin.php '<?php')"
	REPOS --site "$SITE" --plugin "$p" >/dev/null 2>&1
	repo="$SITE/wp-content/plugins/my-plugin"
	echo change >>"$repo/plugin.php"
	git -C "$repo" stash -q
	run bash "$SBX_REPO/scripts/remove.sh" --site "$SITE" --project "$PROJECT" --yes
	[ "$status" -ne 0 ]
	[ -d "$repo" ]
}

@test "refuses a Playground sandbox, where cloned repos would not load" {
	printf 'CLOSEHUB_SANDBOX_NAME=site\nCLOSEHUB_SANDBOX_BACKEND=playground\n' >"$SITE/.env"
	p="$(make_remote my-plugin plugin.php '<?php')"
	run REPOS --site "$SITE" --plugin "$p"
	[ "$status" -ne 0 ]
	[[ "$output" == *"php backend"* ]]
	[ ! -e "$SITE/wp-content/plugins/my-plugin" ]
}
