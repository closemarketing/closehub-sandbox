#!/usr/bin/env bash
# Manage the sandbox entries of <project>/.claude/launch.json, keeping other configurations.
#
# Usage:
#   launch.sh --project DIR --site SITE_DIR   Add or replace the entry of a site; prints its name.
#   launch.sh --project DIR --list            One line per sandbox entry: NAME<TAB>SITE<TAB>ok|missing
#   launch.sh --project DIR --remove NAME     Remove an entry (works even if the site is gone).
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

PROJECT="$PWD"
SITE=""
ACTION="add"
REMOVE_NAME=""
while [ $# -gt 0 ]; do
	case "$1" in
	--project) PROJECT="${2:?}"; shift 2 ;;
	--site) SITE="${2:?}"; shift 2 ;;
	--list) ACTION="list"; shift ;;
	--remove) ACTION="remove"; REMOVE_NAME="${2:?}"; shift 2 ;;
	*) sbx_die "unknown argument: $1" ;;
	esac
done

PROJECT="$(cd "$PROJECT" && pwd)"
FILE="$PROJECT/.claude/launch.json"

# Run one JSON action with PHP or Node (the playground backend may lack PHP).
# Args: action file [name serve site port]. "list" prints NAME<TAB>SITE for sandbox entries.
json_edit() {
	if sbx_has php; then
		# shellcheck disable=SC2016 # PHP code, not shell
		php -r '
		$action = $argv[1]; $file = $argv[2]; $name = $argv[3] ?? "";
		$data = is_file($file) ? json_decode(file_get_contents($file), true) : null;
		if (!is_array($data)) { $data = ["version" => "0.0.1", "configurations" => []]; }
		$configs = $data["configurations"] ?? [];
		if ($action === "list") {
			foreach ($configs as $c) {
				if (str_starts_with($c["name"] ?? "", "closehub-sandbox-")) { echo $c["name"], "\t", $c["runtimeArgs"][1] ?? "", "\n"; }
			}
			exit(0);
		}
		$configs = array_values(array_filter($configs, fn($c) => ($c["name"] ?? "") !== $name));
		if ($action === "add") {
			$configs[] = ["name" => $name, "runtimeExecutable" => "bash", "runtimeArgs" => [$argv[4], $argv[5]], "port" => (int) $argv[6]];
		}
		$data["configurations"] = $configs;
		file_put_contents($file, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
		' "$@"
	elif sbx_has node; then
		# shellcheck disable=SC2016 # JavaScript code, not shell
		node -e '
		const fs = require("fs");
		const [action, file, name, serve, site, port] = process.argv.slice(1);
		let data = null;
		try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) {}
		if (!data || typeof data !== "object") data = { version: "0.0.1", configurations: [] };
		let configs = data.configurations || [];
		if (action === "list") {
			for (const c of configs) {
				if ((c.name || "").startsWith("closehub-sandbox-")) console.log(`${c.name}\t${(c.runtimeArgs || [])[1] || ""}`);
			}
			process.exit(0);
		}
		configs = configs.filter((c) => c.name !== name);
		if (action === "add") configs.push({ name, runtimeExecutable: "bash", runtimeArgs: [serve, site], port: Number(port) });
		data.configurations = configs;
		fs.writeFileSync(file, JSON.stringify(data, null, 4) + "\n");
		' "$@"
	else
		sbx_die "need php or node to edit $FILE"
	fi
}

case "$ACTION" in
list)
	[ -f "$FILE" ] || exit 0
	json_edit list "$FILE" | while IFS="$(printf '\t')" read -r name site; do
		if [ -n "$site" ] && [ -n "$(sbx_env_get "$site/.env" CLOSEHUB_SANDBOX_NAME 2>/dev/null || true)" ]; then
			printf '%s\t%s\tok\n' "$name" "$site"
		else
			printf '%s\t%s\tmissing\n' "$name" "$site"
		fi
	done
	;;
remove)
	[ -f "$FILE" ] || exit 0
	json_edit remove "$FILE" "$REMOVE_NAME"
	sbx_info "removed '$REMOVE_NAME' from $FILE"
	;;
add)
	[ -n "$SITE" ] || sbx_die "--site is required"
	[ -f "$SITE/.env" ] || sbx_die "missing $SITE/.env; run setup.sh first"
	SITE="$(cd "$SITE" && pwd)"
	NAME="closehub-sandbox-$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_NAME)"
	PORT="$(sbx_env_get "$SITE/.env" CLOSEHUB_SANDBOX_PORT)"
	mkdir -p "$PROJECT/.claude"
	json_edit add "$FILE" "$NAME" "$SITE/.closehub-sandbox-bin/serve.sh" "$SITE" "$PORT"
	sbx_info "wrote '$NAME' (port $PORT) to $FILE"
	printf '%s\n' "$NAME"
	;;
esac
