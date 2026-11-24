#!/usr/bin/env bash
# Add or replace the sandbox entry in <project>/.claude/launch.json, keeping other configurations.
#
# Usage: launch.sh --project DIR --site SITE_DIR
# Prints the configuration name (for preview_start) on stdout.
set -euo pipefail

SBX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$SBX_ROOT/scripts/lib.sh"

PROJECT="$PWD"
SITE=""
while [ $# -gt 0 ]; do
	case "$1" in
	--project) PROJECT="${2:?}"; shift 2 ;;
	--site) SITE="${2:?}"; shift 2 ;;
	*) sbx_die "unknown argument: $1" ;;
	esac
done

[ -n "$SITE" ] || sbx_die "--site is required"
[ -f "$SITE/.env" ] || sbx_die "missing $SITE/.env; run setup.sh first"
PROJECT="$(cd "$PROJECT" && pwd)"
SITE="$(cd "$SITE" && pwd)"

NAME="sandboxwp-$(sbx_env_get "$SITE/.env" SANDBOXWP_NAME)"
PORT="$(sbx_env_get "$SITE/.env" SANDBOXWP_PORT)"
SERVE="$SITE/.sandboxwp-bin/serve.sh"
FILE="$PROJECT/.claude/launch.json"
mkdir -p "$PROJECT/.claude"

# JSON merge in PHP, Node or Python: whichever exists (the playground backend may lack PHP).
if sbx_has php; then
	# shellcheck disable=SC2016 # PHP code, not shell
	php -r '
	[, $file, $name, $serve, $site, $port] = $argv;
	$data = is_file($file) ? json_decode(file_get_contents($file), true) : null;
	if (!is_array($data)) { $data = ["version" => "0.0.1", "configurations" => []]; }
	$data["configurations"] = array_values(array_filter($data["configurations"] ?? [], fn($c) => ($c["name"] ?? "") !== $name));
	$data["configurations"][] = ["name" => $name, "runtimeExecutable" => "bash", "runtimeArgs" => [$serve, $site], "port" => (int) $port];
	file_put_contents($file, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
	' "$FILE" "$NAME" "$SERVE" "$SITE" "$PORT"
elif sbx_has node; then
	node -e '
	const fs = require("fs");
	const [file, name, serve, site, port] = process.argv.slice(1);
	let data = null;
	try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) {}
	if (!data || typeof data !== "object") data = { version: "0.0.1", configurations: [] };
	data.configurations = (data.configurations || []).filter((c) => c.name !== name);
	data.configurations.push({ name, runtimeExecutable: "bash", runtimeArgs: [serve, site], port: Number(port) });
	fs.writeFileSync(file, JSON.stringify(data, null, 4) + "\n");
	' "$FILE" "$NAME" "$SERVE" "$SITE" "$PORT"
else
	sbx_die "need php or node to edit $FILE"
fi

sbx_info "wrote '$NAME' (port $PORT) to $FILE"
printf '%s\n' "$NAME"
