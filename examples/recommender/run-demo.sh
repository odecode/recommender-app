#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# Local WSL defaults; explicit environment settings still take precedence.
export BRIEVC="${BRIEVC:-$HOME/briev-target/release/brievc}"
export BRIEV_STDLIB="${BRIEV_STDLIB:-$repo_root/../briev-lang/lib}"
export MOVIELENS_DIR="${MOVIELENS_DIR:-/mnt/c/Users/wotto/AutAI/ml-100k}"
compiler="$BRIEVC"
stdlib_dir="$BRIEV_STDLIB"
config_dir="${BRIEV_CONFIG_DIR:-}"
dataset_dir="$MOVIELENS_DIR"
data_file="${UDATA_PATH:-${dataset_dir:+$dataset_dir/u.data}}"
item_file="${UITEM_PATH:-${dataset_dir:+$dataset_dir/u.item}}"
db_user="${PGUSER:-briev_test}"
db_name="${PGDATABASE:-briev_recommender_test}"
backend_port="${PORT:-8080}"
frontend_port="${FRONTEND_PORT:-8081}"
backend_out="$repo_root/target/recommender-demo"
frontend_out="$repo_root/target/recommender-web"

command -v "$compiler" >/dev/null 2>&1 || {
    echo "Briev compiler not found. Set BRIEVC to its executable path." >&2
    exit 1
}
[[ -n "$stdlib_dir" && -d "$stdlib_dir" ]] || {
    echo "Set BRIEV_STDLIB to the compatible Briev lib directory (containing std)." >&2
    exit 1
}
# 2026-11-01: External compiler caches have no executable-relative config.
# Resolve the companion config explicitly so type widths do not depend on cwd.
# Retire when the compiler ships/discovers its configuration as installed data.
if [[ -d "$stdlib_dir/../config" && -z "$config_dir" ]]; then
    config_dir="$stdlib_dir/../config"
fi
[[ -n "$config_dir" && -d "$config_dir" ]] || {
    echo "Set BRIEV_CONFIG_DIR to the compatible Briev config directory." >&2
    exit 1
}
# The compiler also resolves per-language glue from its resource root.
# A standalone app checkout has no lib/glue of its own.
# Use the installed LLVM tools for IR verification and native linking.
if [[ -d /usr/lib/llvm-17/bin ]]; then export PATH="/usr/lib/llvm-17/bin:$PATH"; fi
export BRIEV_HOME="${BRIEV_HOME:-$(cd "$stdlib_dir/.." && pwd)}"
[[ -d "$BRIEV_HOME/lib/glue" ]] || {
    echo "BRIEV_HOME must contain lib/glue (derived from BRIEV_STDLIB)." >&2
    exit 1
}
command -v python3 >/dev/null 2>&1 || {
    echo "Required command not found: python3" >&2
    exit 1
}
[[ -n "$data_file" && -f "$data_file" ]] || {
    echo "Set UDATA_PATH or MOVIELENS_DIR to the MovieLens u.data file." >&2
    exit 1
}
[[ -n "$item_file" && -f "$item_file" ]] || {
    echo "Set UITEM_PATH or MOVIELENS_DIR to the MovieLens u.item file." >&2
    exit 1
}

# A WSL restart can stop the local database between demo runs.
if command -v pg_isready >/dev/null 2>&1 && ! pg_isready -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "$db_user" -d "$db_name" -t 1 >/dev/null 2>&1; then
    case "${PGHOST:-127.0.0.1}" in
        127.0.0.1|localhost|::1) sudo service postgresql start ;;
        *) echo "PostgreSQL at $PGHOST is unavailable; start it and retry." >&2; exit 1 ;;
    esac
fi
mkdir -p "$backend_out" "$frontend_out"
echo "Building recommender backend..."
"$compiler" build examples/recommender/server.bv --stdlib-path "$stdlib_dir" --config-dir "$config_dir" --out "$backend_out"
echo "Building browser frontend..."
"$compiler" build examples/recommender/app.rbv --stdlib-path "$stdlib_dir" --config-dir "$config_dir" --split --out "$frontend_out"
# The Briev app reads ?api= at startup. Set it from the port this launcher
# actually uses, while allowing an explicit URL override.
python3 - "$frontend_out/app.html" "$backend_port" <<'PY'
from pathlib import Path
import sys
html_path = Path(sys.argv[1])
api_url = f"http://127.0.0.1:{int(sys.argv[2])}"
script = ("<script>if (!new URLSearchParams(location.search).has('api')) { "
          "const url = new URL(location.href); "
          f"url.searchParams.set('api', '{api_url}'); "
          "history.replaceState(null, '', url); }</script>")
html = html_path.read_text(encoding="utf-8")
if "</head>" not in html:
    raise SystemExit("generated app.html has no head element")
html_path.write_text(html.replace("</head>", script + "\n</head>", 1), encoding="utf-8")
PY

backend="$backend_out/server"
[[ -x "$backend" ]] || {
    echo "Backend executable was not produced at $backend" >&2
    exit 1
}

export PGUSER="$db_user" PGDATABASE="$db_name"
export UDATA_PATH="$data_file" UITEM_PATH="$item_file" PORT="$backend_port"
python3 -m http.server "$frontend_port" --bind 127.0.0.1 --directory "$frontend_out" &
http_pid=$!
cleanup() {
    kill "$http_pid" 2>/dev/null || true
    wait "$http_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Frontend: http://localhost:$frontend_port/app.html"
echo "Backend:  http://127.0.0.1:$backend_port"
echo "Database: $db_user@$db_name (local PostgreSQL on 127.0.0.1:5432)"
echo "Keep this terminal open; press Ctrl+C to stop the demo."
"$backend"
