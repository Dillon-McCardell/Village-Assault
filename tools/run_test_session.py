#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT_DIR / "village-assault"
DEFAULT_ADDRESS = "127.0.0.1"
DEFAULT_TIMEOUT_SEC = 25.0


class SessionError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch a deterministic Village Assault map and troop test session."
    )
    parser.add_argument("scenario", help="Path to a custom test-session JSON file.")
    parser.add_argument("--players", type=int, choices=[1, 2], default=1)
    parser.add_argument("--godot-bin", help="Path to the Godot executable.")
    parser.add_argument("--artifacts-dir", help="Directory for event and process logs.")
    parser.add_argument("--timeout-sec", type=float, default=DEFAULT_TIMEOUT_SEC)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument(
        "--exit-after-ready",
        action="store_true",
        help="Exit after every process reports that the scenario is ready.",
    )
    return parser.parse_args()


def resolve_godot_binary(explicit_path: str | None) -> str:
    candidates = [
        explicit_path,
        os.environ.get("GODOT_BIN"),
        str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"),
        shutil.which("godot4"),
        shutil.which("godot"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    raise SessionError("Godot binary not found. Pass --godot-bin or set GODOT_BIN.")


def load_scenario(path_value: str) -> tuple[Path, dict[str, Any]]:
    path = Path(path_value).expanduser().resolve()
    if not path.is_file():
        raise SessionError(f"Scenario does not exist: {path}")
    try:
        scenario = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise SessionError(f"Invalid scenario JSON at line {error.lineno}: {error.msg}") from error
    if not isinstance(scenario, dict):
        raise SessionError("Scenario root must be a JSON object.")
    return path, scenario


def choose_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((DEFAULT_ADDRESS, 0))
        return int(sock.getsockname()[1])


def make_artifacts_dir(explicit_dir: str | None) -> Path:
    if explicit_dir:
        path = Path(explicit_dir).expanduser().resolve()
        path.mkdir(parents=True, exist_ok=True)
        return path
    return Path(tempfile.mkdtemp(prefix="village-assault-session-")).resolve()


def launch_process(
    *,
    role: str,
    godot_bin: str,
    scenario_path: Path,
    player_count: int,
    artifacts_dir: Path,
    run_id: str,
    port: int,
    headless: bool,
) -> subprocess.Popen[Any]:
    stdout_path = artifacts_dir / f"{run_id}_{role}.stdout.log"
    stderr_path = artifacts_dir / f"{run_id}_{role}.stderr.log"
    command = [godot_bin]
    if headless:
        command.append("--headless")
    else:
        x_position = 30 if role == "host" else 760
        command.extend(["--position", f"{x_position},60"])
    command.extend(
        [
            "--path",
            str(PROJECT_DIR),
            "--",
            "--test-mode",
            "--test-role",
            role,
            "--test-address",
            DEFAULT_ADDRESS,
            "--test-port",
            str(port),
            "--test-artifacts-dir",
            str(artifacts_dir),
            "--test-run-id",
            run_id,
            "--test-scenario",
            "custom_session",
            "--test-session-config",
            str(scenario_path),
            "--test-session-players",
            str(player_count),
        ]
    )
    with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        return subprocess.Popen(
            command,
            cwd=str(ROOT_DIR),
            stdout=stdout_handle,
            stderr=stderr_handle,
            text=True,
        )


def read_events(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    events = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            events.append(json.loads(line))
    return events


def wait_for_event(
    *,
    role: str,
    event_name: str,
    process: subprocess.Popen[Any],
    event_path: Path,
    timeout_sec: float,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        for event in read_events(event_path):
            if event.get("role") == role and event.get("event") == event_name:
                return event
            if event.get("event") == "failure":
                raise SessionError(f"{role} reported failure: {event.get('message', event)}")
        if process.poll() is not None:
            raise SessionError(f"{role} exited with code {process.returncode} before {event_name}.")
        time.sleep(0.1)
    raise SessionError(f"Timed out waiting for {role} {event_name}.")


def terminate_processes(processes: list[subprocess.Popen[Any]]) -> None:
    for process in processes:
        if process.poll() is None:
            process.terminate()
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline and any(process.poll() is None for process in processes):
        time.sleep(0.1)
    for process in processes:
        if process.poll() is None:
            process.kill()


def main() -> int:
    args = parse_args()
    processes: list[subprocess.Popen[Any]] = []
    try:
        scenario_path, scenario = load_scenario(args.scenario)
        godot_bin = resolve_godot_binary(args.godot_bin)
        artifacts_dir = make_artifacts_dir(args.artifacts_dir)
        port = choose_free_port()
        run_id = time.strftime("session_%Y%m%d_%H%M%S")

        host = launch_process(
            role="host",
            godot_bin=godot_bin,
            scenario_path=scenario_path,
            player_count=args.players,
            artifacts_dir=artifacts_dir,
            run_id=run_id,
            port=port,
            headless=args.headless,
        )
        processes.append(host)
        host_events = artifacts_dir / f"{run_id}_host.events.jsonl"
        wait_for_event(
            role="host",
            event_name="boot_ready",
            process=host,
            event_path=host_events,
            timeout_sec=args.timeout_sec,
        )

        roles = [("host", host, host_events)]
        if args.players == 2:
            client = launch_process(
                role="client",
                godot_bin=godot_bin,
                scenario_path=scenario_path,
                player_count=args.players,
                artifacts_dir=artifacts_dir,
                run_id=run_id,
                port=port,
                headless=args.headless,
            )
            processes.append(client)
            roles.append(("client", client, artifacts_dir / f"{run_id}_client.events.jsonl"))

        for role, process, event_path in roles:
            wait_for_event(
                role=role,
                event_name="custom_session_ready",
                process=process,
                event_path=event_path,
                timeout_sec=args.timeout_sec,
            )

        session_name = scenario.get("name", scenario_path.stem)
        print(f"Test session ready: {session_name}")
        print(f"Scenario: {scenario_path}")
        print(f"Artifacts: {artifacts_dir}")
        print("Processes: " + ", ".join(f"{role}={process.pid}" for role, process, _ in roles))
        if args.exit_after_ready:
            return 0
        print("Press Ctrl-C to stop the session.")
        while all(process.poll() is None for process in processes):
            time.sleep(0.25)
        return max((process.returncode or 0) for process in processes)
    except KeyboardInterrupt:
        return 0
    except SessionError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        terminate_processes(processes)


if __name__ == "__main__":
    raise SystemExit(main())
