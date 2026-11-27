#!/usr/bin/env bash
# Shared helpers for closehub-sandbox scripts. Sourced, never executed.
# Must stay compatible with bash 3.2 (macOS) and GNU/Linux.

SBX_DEFAULT_PORT=8080
SBX_MIN_PHP="8.1.0"

sbx_info() { printf '[closehub-sandbox] %s\n' "$*" >&2; }
sbx_warn() { printf '[closehub-sandbox] WARNING: %s\n' "$*" >&2; }
sbx_die() {
	printf '[closehub-sandbox] ERROR: %s\n' "$*" >&2
	exit 1
}

sbx_has() { command -v "$1" >/dev/null 2>&1; }

# Xdebug trying to reach a debugger slows every PHP call; keep it off unless the user set it.
export XDEBUG_MODE="${XDEBUG_MODE:-off}"

# Sites live in ~/SandBox/<name> (like WordPress Studio uses ~/Studio). Override with CLOSEHUB_SANDBOX_HOME.
sbx_home() { printf '%s\n' "${CLOSEHUB_SANDBOX_HOME:-$HOME/SandBox}"; }

sbx_php_ok() {
	sbx_has php || return 1
	php -r "exit(version_compare(PHP_VERSION, '$SBX_MIN_PHP', '>=') ? 0 : 1);" 2>/dev/null
}

# Absolute path without requiring the directory to exist (it may be created later).
sbx_abspath() {
	local p="$1"
	# Literal ~ (quoted by the caller): expand it ourselves.
	# shellcheck disable=SC2088
	case "$p" in
	"~") p="$HOME" ;;
	"~/"*) p="$HOME/${p#\~/}" ;;
	/*) ;;
	*) p="$PWD/$p" ;;
	esac
	if [ -d "$p" ]; then
		(cd "$p" && pwd)
	else
		printf '%s\n' "${p%/}"
	fi
}

# 0 if a directory has nothing that WordPress files could clash with. Agent/editor/VCS files are fine.
sbx_dir_is_free() {
	local dir="$1" f
	[ -d "$dir" ] || return 0
	for f in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		case "$(basename "$f")" in
		.claude | .DS_Store | .git | .gitignore | .gitattributes | AGENTS.md | CLAUDE.md | README.md) ;;
		*) return 1 ;;
		esac
	done
	return 0
}

# Lowercase slug safe for directory names and WordPress plugin/theme slugs.
sbx_slug() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# 0 if something is listening on 127.0.0.1:<port>. Uses bash /dev/tcp: no nc/lsof dependency.
sbx_port_in_use() {
	(exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1
}

sbx_free_port() {
	local port="${1:-$SBX_DEFAULT_PORT}" max
	max=$((port + 100))
	while [ "$port" -lt "$max" ]; do
		if ! sbx_port_in_use "$port"; then
			printf '%s\n' "$port"
			return 0
		fi
		port=$((port + 1))
	done
	return 1
}

# Detect what the project is from its files: plugin | theme | none | ambiguous.
# Only a fallback: the project's AGENTS.md is the source of truth (see AGENTS.md of this plugin).
sbx_detect_type() {
	local dir="$1" is_plugin=0 is_theme=0 f
	for f in "$dir"/*.php; do
		[ -f "$f" ] || continue
		if head -n 30 "$f" | grep -qE '^[[:space:]/*#@]*Plugin Name:'; then
			is_plugin=1
			break
		fi
	done
	if [ -f "$dir/style.css" ] && head -n 30 "$dir/style.css" | grep -qE 'Theme Name:'; then
		is_theme=1
	fi
	if [ "$is_plugin" = 1 ] && [ "$is_theme" = 1 ]; then
		echo ambiguous
	elif [ "$is_plugin" = 1 ]; then
		echo plugin
	elif [ "$is_theme" = 1 ]; then
		echo theme
	else
		echo none
	fi
}

# .env helpers. Values are written unquoted; keys are [A-Z0-9_].
sbx_env_get() {
	local file="$1" key="$2"
	[ -f "$file" ] || return 1
	grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2-
}

sbx_env_set() {
	local file="$1" key="$2" value="$3" tmp
	tmp="$(mktemp)"
	if [ -f "$file" ]; then
		grep -vE "^${key}=" "$file" >"$tmp" || true
	fi
	printf '%s=%s\n' "$key" "$value" >>"$tmp"
	mv "$tmp" "$file"
	chmod 600 "$file"
}

# Export every KEY=value line of a .env file into the environment.
sbx_env_load() {
	local file="$1" line key
	[ -f "$file" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in '' | \#*) continue ;; esac
		key="${line%%=*}"
		case "$key" in *[!A-Za-z0-9_]* | '') continue ;; esac
		export "$key=${line#*=}"
	done <"$file"
}

# Install the SQLite drop-in (sqlite-database-integration + wp-content/db.php) into a site.
# Usage: sbx_install_sqlite SITE
sbx_install_sqlite() {
	local site="$1" dir zip
	dir="$site/wp-content/plugins/sqlite-database-integration"
	if [ ! -f "$dir/db.copy" ]; then
		zip="$(mktemp)"
		curl -fsSL -o "$zip" https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip ||
			sbx_die "could not download sqlite-database-integration"
		unzip -q -o "$zip" -d "$site/wp-content/plugins"
		rm -f "$zip"
	fi
	[ -f "$dir/db.copy" ] || sbx_die "unexpected sqlite-database-integration layout (db.copy missing)"
	# Relative path via __DIR__ keeps the site movable.
	# shellcheck disable=SC2016 # PHP code, not shell
	php -r 'file_put_contents($argv[2], strtr(file_get_contents($argv[1]), [$argv[3] => $argv[4], $argv[5] => $argv[6]]));' \
		"$dir/db.copy" "$site/wp-content/db.php" \
		"'{SQLITE_IMPLEMENTATION_FOLDER_PATH}'" "__DIR__ . '/plugins/sqlite-database-integration'" \
		"{SQLITE_PLUGIN}" "sqlite-database-integration/load.php"
}
