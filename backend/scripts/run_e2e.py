"""Run the browser suite against an isolated local PostgreSQL/Backend/Web stack."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
from urllib.request import urlopen
from uuid import uuid4

from dotenv import dotenv_values
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.pool import NullPool

BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND.parent
WEB = ROOT / "web"
ARTIFACTS = WEB / ".e2e-artifacts"
sys.path.insert(0, str(BACKEND))

from app.db.database_target import (  # noqa: E402
    DatabasePurpose, UnsafeDatabaseTarget, validate_disposable_database_url,
)


def database_target(value: str | None) -> URL:
    if not value:
        raise UnsafeDatabaseTarget("Set E2E_DATABASE_URL or backend/.env.e2e")
    url = validate_disposable_database_url(value, DatabasePurpose.E2E)
    if (url.host or "").lower() not in {"localhost", "127.0.0.1", "::1"}:
        raise UnsafeDatabaseTarget("E2E requires a loopback PostgreSQL host")
    # libpq query parameters can override the apparent host/database/user.
    if set(url.query) - {"sslmode", "connect_timeout"}:
        raise UnsafeDatabaseTarget("E2E URL accepts only sslmode/connect_timeout options")
    return url


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


def wait_for_backend(process: subprocess.Popen, base: str) -> None:
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Backend exited; inspect backend.log")
        try:
            with urlopen(base + "/health", timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            pass
        time.sleep(0.2)
    raise RuntimeError("Backend readiness timed out; inspect backend.log")


def run(*, headed: bool = False) -> int:
    values = dotenv_values(BACKEND / ".env.e2e")
    url = database_target(os.environ.get("E2E_DATABASE_URL") or values.get("E2E_DATABASE_URL"))
    npm = shutil.which("npm")
    if not npm:
        raise RuntimeError("Install Node.js 22 and npm first")
    schema = "e2e_" + uuid4().hex
    agent_schema = schema + "_agent"
    api_port, web_port = free_port(), free_port()
    while api_port == web_port:
        web_port = free_port()
    api = f"http://127.0.0.1:{api_port}"
    web = f"http://127.0.0.1:{web_port}"
    scoped = url.update_query_dict({"options": f"-csearch_path={schema}"}).render_as_string(hide_password=False)
    env = os.environ.copy()
    env.update({
        "DATABASE_URL": scoped, "DATABASE_URL_DIRECT": scoped,
        "AGENT_DATABASE_URL": scoped, "AGENT_DATABASE_SCHEMA": agent_schema,
        "JWT_SECRET_KEY": secrets.token_urlsafe(48),
        "CORS_ORIGINS": json.dumps([web]),
        "AGENT_MODEL": "e2e-disabled", "AGENT_API_KEY": "e2e-not-a-real-key",
        "AGENT_API_BASE": "http://127.0.0.1:1/v1",
        "AGENT_MAX_RETRIES": "0", "AGENT_TIMEOUT_SECONDS": "1",
        "APP_VERSION": "0.0.0-e2e", "APP_COMMIT_SHA": "0000000",
        "VITE_API_BASE_URL": api + "/api/v1",
        "E2E_BASE_URL": web, "E2E_WEB_PORT": str(web_port),
        "E2E_SLOW_MO_MS": "700" if headed else "0",
    })
    if ARTIFACTS.exists():
        shutil.rmtree(ARTIFACTS)
    ARTIFACTS.mkdir()
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    dirty = bool(subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip())
    (ARTIFACTS / "run-info.json").write_text(json.dumps({"commit": revision, "working_tree_dirty": dirty, "schema": schema, "agent_schema": agent_schema, "backend": api, "web": web}, indent=2))
    engine = create_engine(url, poolclass=NullPool, hide_parameters=True, connect_args={"connect_timeout": 10})
    process = None
    try:
        with (ARTIFACTS / "initialize.log").open("w") as log:
            subprocess.run([sys.executable, "scripts/initialize_database.py", "--business-schema", schema], cwd=BACKEND, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        with (ARTIFACTS / "backend.log").open("w") as log:
            process = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", str(api_port)], cwd=BACKEND, env=env, stdout=log, stderr=subprocess.STDOUT)
            wait_for_backend(process, api)
            print("Isolated Backend ready; starting real-browser E2E", flush=True)
            command = [npm, "run", "test:e2e"]
            if headed:
                command.extend(["--", "--headed"])
            return subprocess.run(command, cwd=WEB, env=env, check=False).returncode
    finally:
        if process is not None:
            stop(process)
        try:
            with engine.begin() as connection:
                for name in (agent_schema, schema):
                    quoted = engine.dialect.identifier_preparer.quote(name)
                    connection.exec_driver_sql(f"DROP SCHEMA IF EXISTS {quoted} CASCADE")
            print("E2E schemas cleaned up", flush=True)
        finally:
            engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headed", action="store_true", help="Show Chromium and slow browser actions for observation")
    args = parser.parse_args()
    try:
        raise SystemExit(run(headed=args.headed))
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:
        # Do not print connection strings/driver exceptions to the terminal.
        message = str(error) if isinstance(error, UnsafeDatabaseTarget) else type(error).__name__
        print(f"E2E failed: {message}. Inspect web/.e2e-artifacts/", file=sys.stderr)
        raise SystemExit(1)
