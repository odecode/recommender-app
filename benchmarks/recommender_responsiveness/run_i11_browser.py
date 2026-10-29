#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the I11 real browser/server integration gate.

Builds the native server and split WASM app with the supplied compiler, starts
the server on a private port, then runs browser_live_server.mjs. The runner
retains build logs, source/artifact hashes, the server log and the gate result.
It stops only the server process it starts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_build(command: list[str], log: Path, env: dict[str, str]) -> None:
    with log.open("w") as handle:
        completed = subprocess.run(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT)
    if completed.returncode != 0:
        raise RuntimeError(f"build failed ({completed.returncode}); see {log}")


def wait_for_movies(url: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    last_error = "not started"
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                if response.status == 200:
                    return
                last_error = f"HTTP {response.status}"
        except Exception as error:  # noqa: BLE001 - report the last probe failure
            last_error = str(error)
        time.sleep(1)
    raise RuntimeError(f"server did not become ready at {url}: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path, help="path to brievc")
    parser.add_argument("--output", required=True, type=Path, help="new directory for logs/artifacts")
    parser.add_argument("--stdlib", type=Path, help="compiler stdlib root (default: compiler repo lib)")
    parser.add_argument("--port", type=int, default=18110)
    parser.add_argument("--ready-timeout", type=float, default=120.0)
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    if not compiler.is_file():
        parser.error(f"compiler not found: {compiler}")
    stdlib = (args.stdlib or compiler.parents[2] / "lib").resolve()
    if not (stdlib / "std").is_dir():
        parser.error(f"stdlib root has no std/: {stdlib}")
    output = args.output.resolve()
    if output.exists():
        parser.error(f"output directory already exists: {output}")
    for name in ("PGUSER", "PGDATABASE", "UDATA_PATH", "UITEM_PATH", "PLAYWRIGHT_MODULE"):
        if not os.environ.get(name):
            parser.error(f"{name} must be set")
    if not os.environ.get("PSQL") and shutil.which("psql") is None:
        parser.error("psql must be on PATH or set PSQL")

    output.mkdir(parents=True)
    server_dir = output / "server"
    web_dir = output / "web"
    server_src = ROOT / "examples" / "recommender" / "server.bv"
    app_src = ROOT / "examples" / "recommender" / "app.rbv"
    server_log = output / "server.log"
    gate_log = output / "gate.log"
    build_env = os.environ.copy()

    summary: dict[str, object] = {
        "gate": "I11 real browser/server integration",
        "compiler": str(compiler),
        "stdlib": str(stdlib),
        "port": args.port,
        "output": str(output),
    }
    server: subprocess.Popen[bytes] | None = None
    gate_rc = 1
    try:
        run_build([str(compiler), "build", str(server_src), "--stdlib-path", str(stdlib), "--out", str(server_dir)],
                  output / "server-build.log", build_env)
        run_build([str(compiler), "build", str(app_src), "--stdlib-path", str(stdlib), "--split", "--out", str(web_dir)],
                  output / "app-build.log", build_env)

        artifacts = [server_dir / "server", web_dir / "app.wasm", web_dir / "app.mjs"]
        missing = [str(path) for path in artifacts if not path.is_file()]
        if missing:
            raise RuntimeError("build did not produce: " + ", ".join(missing))

        server_env = os.environ.copy()
        server_env["PORT"] = str(args.port)
        server = subprocess.Popen([str(server_dir / "server")], cwd=ROOT, env=server_env,
                                  stdout=server_log.open("wb"), stderr=subprocess.STDOUT)
        api = f"http://127.0.0.1:{args.port}"
        wait_for_movies(f"{api}/movies", args.ready_timeout)

        node = os.environ.get("NODE", "node")
        gate_env = os.environ.copy()
        gate_env.setdefault("PLAYWRIGHT_CHANNEL", "chromium")
        module_dir = Path(gate_env["PLAYWRIGHT_MODULE"]).parent
        if module_dir.name == "node_modules":
            gate_env.setdefault("NODE_PATH", str(module_dir))
        with gate_log.open("w") as handle:
            gate = subprocess.run(
                [node, str(ROOT / "tests/fixtures/recommender/browser_live_server.mjs"), str(web_dir), api],
                cwd=ROOT, env=gate_env, stdout=handle, stderr=subprocess.STDOUT,
            )
        gate_rc = gate.returncode
        lines = [line for line in gate_log.read_text().splitlines() if line.strip()]
        if lines:
            try:
                summary["gate_result"] = json.loads(lines[-1])
            except json.JSONDecodeError:
                summary["gate_result"] = {"raw": lines[-1]}
        summary["gate_exit"] = gate_rc
        summary["sources"] = {str(path.relative_to(ROOT)): sha256(path) for path in (server_src, app_src)}
        summary["artifacts"] = {str(path.relative_to(output)): sha256(path) for path in artifacts}
    except Exception as error:  # noqa: BLE001 - retain evidence for the caller
        summary["error"] = str(error)
    finally:
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, sort_keys=True))
    return gate_rc if "error" not in summary else 1


if __name__ == "__main__":
    sys.exit(main())
