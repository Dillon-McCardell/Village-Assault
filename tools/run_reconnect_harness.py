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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT_DIR / "village-assault"
DEFAULT_ADDRESS = "127.0.0.1"
POLL_INTERVAL_SEC = 0.1
DEFAULT_TIMEOUT_SEC = 25.0
SCENARIO_GAME_RECONNECT = "game_reconnect"
SCENARIO_LOBBY_RECONNECT = "lobby_reconnect"


class HarnessError(RuntimeError):
    pass


@dataclass
class EventReader:
    path: Path
    role: str
    offset: int = 0
    events: list[dict[str, Any]] = field(default_factory=list)

    def poll(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        new_events: list[dict[str, Any]] = []
        with self.path.open("r", encoding="utf-8") as handle:
            handle.seek(self.offset)
            for raw_line in handle:
                line = raw_line.strip()
                if not line:
                    continue
                payload = json.loads(line)
                self.events.append(payload)
                new_events.append(payload)
            self.offset = handle.tell()
        return new_events

    def last_event(self) -> dict[str, Any] | None:
        return self.events[-1] if self.events else None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the local reconnection acceptance harness.")
    parser.add_argument("--godot-bin", help="Path to the Godot executable.")
    parser.add_argument(
        "--artifacts-dir",
        help="Directory for child event and log artifacts. Defaults to a temp directory.",
    )
    parser.add_argument(
        "--timeout-sec",
        type=float,
        default=DEFAULT_TIMEOUT_SEC,
        help="Per-barrier timeout in seconds.",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Launch Godot child processes in headless mode.",
    )
    parser.add_argument(
        "--scenario",
        choices=[SCENARIO_GAME_RECONNECT, SCENARIO_LOBBY_RECONNECT],
        default=SCENARIO_GAME_RECONNECT,
        help="Reconnect scenario to execute.",
    )
    return parser.parse_args()


def resolve_godot_binary(explicit_path: str | None) -> str:
    candidates = [
        explicit_path,
        os.environ.get("GODOT_BIN"),
        shutil.which("godot4"),
        shutil.which("godot"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    raise HarnessError("Godot binary not found. Pass --godot-bin or set GODOT_BIN.")


def choose_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((DEFAULT_ADDRESS, 0))
        return int(sock.getsockname()[1])


def make_artifacts_dir(explicit_dir: str | None) -> Path:
    if explicit_dir:
        path = Path(explicit_dir).resolve()
        path.mkdir(parents=True, exist_ok=True)
        return path
    return Path(tempfile.mkdtemp(prefix="village-assault-reconnect-")).resolve()


def launch_child(
    *,
    role: str,
    godot_bin: str,
    artifacts_dir: Path,
    run_id: str,
    port: int,
    headless: bool,
    scenario: str,
) -> tuple[subprocess.Popen[Any], EventReader]:
    event_path = artifacts_dir / f"{run_id}_{role}.events.jsonl"
    stdout_path = artifacts_dir / f"{run_id}_{role}.stdout.log"
    stderr_path = artifacts_dir / f"{run_id}_{role}.stderr.log"

    cmd = [godot_bin]
    if headless:
        cmd.append("--headless")
    cmd.extend(
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
            scenario,
        ]
    )

    stdout_handle = stdout_path.open("w", encoding="utf-8")
    stderr_handle = stderr_path.open("w", encoding="utf-8")
    process = subprocess.Popen(
        cmd,
        cwd=str(ROOT_DIR),
        stdout=stdout_handle,
        stderr=stderr_handle,
        text=True,
    )
    return process, EventReader(path=event_path, role=role)


def wait_for_event(
    *,
    readers: list[EventReader],
    processes: list[subprocess.Popen[Any]],
    predicate,
    timeout_sec: float,
    label: str,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        for reader in readers:
            for event in reader.events:
                if predicate(event):
                    return event
        for process in processes:
            if process.poll() is not None and process.returncode != 0:
                raise HarnessError(f"Child process exited early with code {process.returncode} while waiting for {label}.")
        for reader in readers:
            for event in reader.poll():
                if predicate(event):
                    return event
        time.sleep(POLL_INTERVAL_SEC)
    raise HarnessError(f"Timed out waiting for {label}.")


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise HarnessError(message)


def summarize_last_events(readers: list[EventReader]) -> str:
    lines = []
    for reader in readers:
        lines.append(f"{reader.role}: {json.dumps(reader.last_event(), sort_keys=True)}")
    return "\n".join(lines)


def terminate_processes(processes: list[subprocess.Popen[Any]]) -> None:
    for process in processes:
        if process.poll() is None:
            process.terminate()
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        if all(process.poll() is not None for process in processes):
            return
        time.sleep(0.1)
    for process in processes:
        if process.poll() is None:
            process.kill()


def main() -> int:
    args = parse_args()
    godot_bin = resolve_godot_binary(args.godot_bin)
    artifacts_dir = make_artifacts_dir(args.artifacts_dir)
    port = choose_free_port()
    run_id = time.strftime("reconnect_%Y%m%d_%H%M%S")

    processes: list[subprocess.Popen[Any]] = []
    readers: list[EventReader] = []

    try:
        host_process, host_reader = launch_child(
            role="host",
            godot_bin=godot_bin,
            artifacts_dir=artifacts_dir,
            run_id=run_id,
            port=port,
            headless=args.headless,
            scenario=args.scenario,
        )
        processes.append(host_process)
        readers.append(host_reader)

        wait_for_event(
            readers=readers,
            processes=processes,
            predicate=lambda event: event.get("role") == "host" and event.get("event") == "boot_ready",
            timeout_sec=args.timeout_sec,
            label="host boot_ready",
        )

        client_process, client_reader = launch_child(
            role="client",
            godot_bin=godot_bin,
            artifacts_dir=artifacts_dir,
            run_id=run_id,
            port=port,
            headless=args.headless,
            scenario=args.scenario,
        )
        processes.append(client_process)
        readers.append(client_reader)

        host_lobby_event = wait_for_event(
            readers=readers,
            processes=processes,
            predicate=lambda event: event.get("role") == "host" and event.get("event") == "lobby_ready",
            timeout_sec=args.timeout_sec,
            label="host lobby_ready",
        )
        wait_for_event(
            readers=readers,
            processes=processes,
            predicate=lambda event: event.get("role") == "client" and event.get("event") == "connected",
            timeout_sec=args.timeout_sec,
            label="client connected",
        )
        client_lobby_event = wait_for_event(
            readers=readers,
            processes=processes,
            predicate=lambda event: event.get("role") == "client" and event.get("event") == "lobby_ready",
            timeout_sec=args.timeout_sec,
            label="client lobby_ready",
        )
        host_lobby_count_event = wait_for_event(
            readers=readers,
            processes=processes,
            predicate=lambda event: (
                event.get("role") == "host"
                and event.get("event") == "lobby_state_changed"
                and int(event.get("player_count", 0)) >= 2
            ),
            timeout_sec=args.timeout_sec,
            label="host lobby player_count >= 2",
        )
        assert_true(
            int(host_lobby_count_event["player_count"]) >= 2,
            "Host lobby never observed the client joining.",
        )
        if args.scenario == SCENARIO_GAME_RECONNECT:
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "game_ready",
                timeout_sec=args.timeout_sec,
                label="host game_ready",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "game_ready",
                timeout_sec=args.timeout_sec,
                label="client game_ready",
            )

            spawn_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "spawn_confirmed",
                timeout_sec=args.timeout_sec,
                label="host spawn_confirmed",
            )
            unit_id = int(spawn_event["unit_id"])

            pre_disconnect_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "pre_disconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="client pre_disconnect snapshot",
            )
            pre_disconnect_snapshot = pre_disconnect_event["snapshot"]
            assert_true(
                unit_id in pre_disconnect_snapshot.get("visible_unit_ids", []),
                f"Client pre-disconnect snapshot did not include spawned unit {unit_id}.",
            )
            pre_disconnect_team = pre_disconnect_snapshot["local_team"]
            pre_disconnect_money = pre_disconnect_snapshot["local_money"]
            pre_disconnect_width = pre_disconnect_snapshot["map_width"]
            pre_disconnect_height = pre_disconnect_snapshot["map_height"]
            pre_disconnect_seed = pre_disconnect_snapshot["map_seed"]

            host_disconnected_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "disconnected",
                timeout_sec=args.timeout_sec,
                label="host disconnected snapshot",
            )
            host_disconnected_snapshot = host_disconnected_event["snapshot"]
            assert_true(host_disconnected_snapshot["paused"] is True, "Host should be paused after client disconnect.")
            assert_true(
                host_disconnected_snapshot["disconnect_overlay_visible"] is True,
                "Host disconnect overlay should be visible after client disconnect.",
            )

            client_disconnected_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "disconnected"
                    and event.get("reason") == "local_disconnected"
                ),
                timeout_sec=args.timeout_sec,
                label="client disconnected snapshot",
            )
            client_disconnected_snapshot = client_disconnected_event["snapshot"]
            assert_true(client_disconnected_snapshot["paused"] is True, "Client should be paused after local disconnect.")
            assert_true(
                client_disconnected_snapshot["disconnect_overlay_visible"] is True,
                "Client disconnect overlay should be visible after local disconnect.",
            )

            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "reconnect_started",
                timeout_sec=args.timeout_sec,
                label="client reconnect_started",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "reconnect_succeeded",
                timeout_sec=args.timeout_sec,
                label="client reconnect_succeeded",
            )

            host_post_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "host"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "post_reconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="host post_reconnect snapshot",
            )
            client_post_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "post_reconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="client post_reconnect snapshot",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "complete",
                timeout_sec=args.timeout_sec,
                label="host complete",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "complete",
                timeout_sec=args.timeout_sec,
                label="client complete",
            )

            host_post_snapshot = host_post_event["snapshot"]
            client_post_snapshot = client_post_event["snapshot"]

            assert_true(host_post_snapshot["scene"] == "game", "Host should remain in game after reconnect.")
            assert_true(client_post_snapshot["scene"] == "game", "Client should remain in game after reconnect.")
            assert_true(host_post_snapshot["paused"] is False, "Host should be unpaused after reconnect.")
            assert_true(client_post_snapshot["paused"] is False, "Client should be unpaused after reconnect.")
            assert_true(
                client_post_snapshot["local_team"] == pre_disconnect_team,
                "Client team changed across reconnect.",
            )
            assert_true(
                client_post_snapshot["local_money"] == pre_disconnect_money,
                "Client money changed across reconnect.",
            )
            assert_true(
                client_post_snapshot["map_width"] == pre_disconnect_width
                and client_post_snapshot["map_height"] == pre_disconnect_height
                and client_post_snapshot["map_seed"] == pre_disconnect_seed,
                "Client world settings changed across reconnect.",
            )
            assert_true(
                unit_id in client_post_snapshot.get("visible_unit_ids", []),
                f"Client post-reconnect snapshot did not include unit {unit_id}.",
            )
        else:
            host_lobby_snapshot = host_lobby_event["snapshot"]
            client_lobby_snapshot = client_lobby_event["snapshot"]
            assert_true(host_lobby_snapshot["scene"] == "lobby", "Host should start in lobby.")
            assert_true(client_lobby_snapshot["scene"] == "lobby", "Client should start in lobby.")

            pre_disconnect_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "pre_disconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="client pre_disconnect lobby snapshot",
            )
            pre_disconnect_snapshot = pre_disconnect_event["snapshot"]
            pre_disconnect_team = pre_disconnect_snapshot["local_team"]
            pre_disconnect_money = pre_disconnect_snapshot["local_money"]
            pre_disconnect_width = pre_disconnect_snapshot["map_width"]
            pre_disconnect_height = pre_disconnect_snapshot["map_height"]
            pre_disconnect_seed = pre_disconnect_snapshot["map_seed"]
            pre_disconnect_players = pre_disconnect_snapshot["player_count"]
            assert_true(pre_disconnect_players == 2, "Lobby should have two players before disconnect.")

            host_disconnected_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "disconnected",
                timeout_sec=args.timeout_sec,
                label="host disconnected lobby snapshot",
            )
            host_disconnected_snapshot = host_disconnected_event["snapshot"]
            assert_true(host_disconnected_snapshot["scene"] == "lobby", "Host should remain in lobby after disconnect.")
            assert_true(
                host_disconnected_snapshot["disconnect_overlay_visible"] is True,
                "Host disconnect overlay should be visible in lobby after client disconnect.",
            )

            client_disconnected_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "disconnected"
                    and event.get("reason") == "local_disconnected"
                ),
                timeout_sec=args.timeout_sec,
                label="client disconnected lobby snapshot",
            )
            client_disconnected_snapshot = client_disconnected_event["snapshot"]
            assert_true(client_disconnected_snapshot["scene"] == "lobby", "Client should disconnect from lobby.")
            assert_true(
                client_disconnected_snapshot["disconnect_overlay_visible"] is True,
                "Client disconnect overlay should be visible in lobby after local disconnect.",
            )

            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "reconnect_started",
                timeout_sec=args.timeout_sec,
                label="client reconnect_started lobby",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "reconnect_succeeded",
                timeout_sec=args.timeout_sec,
                label="client reconnect_succeeded lobby",
            )

            host_post_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "host"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "post_reconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="host post_reconnect lobby snapshot",
            )
            client_post_event = wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: (
                    event.get("role") == "client"
                    and event.get("event") == "snapshot"
                    and event.get("stage") == "post_reconnect"
                ),
                timeout_sec=args.timeout_sec,
                label="client post_reconnect lobby snapshot",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "host" and event.get("event") == "complete",
                timeout_sec=args.timeout_sec,
                label="host complete lobby",
            )
            wait_for_event(
                readers=readers,
                processes=processes,
                predicate=lambda event: event.get("role") == "client" and event.get("event") == "complete",
                timeout_sec=args.timeout_sec,
                label="client complete lobby",
            )

            host_post_snapshot = host_post_event["snapshot"]
            client_post_snapshot = client_post_event["snapshot"]
            assert_true(host_post_snapshot["scene"] == "lobby", "Host should remain in lobby after reconnect.")
            assert_true(client_post_snapshot["scene"] == "lobby", "Client should return to lobby after reconnect.")
            assert_true(
                client_post_snapshot["local_team"] == pre_disconnect_team,
                "Client team changed across lobby reconnect.",
            )
            assert_true(
                client_post_snapshot["local_money"] == pre_disconnect_money,
                "Client money changed across lobby reconnect.",
            )
            assert_true(
                client_post_snapshot["map_width"] == pre_disconnect_width
                and client_post_snapshot["map_height"] == pre_disconnect_height
                and client_post_snapshot["map_seed"] == pre_disconnect_seed,
                "Client world settings changed across lobby reconnect.",
            )
            assert_true(
                client_post_snapshot["disconnect_overlay_visible"] is False,
                "Client overlay should be hidden after lobby reconnect.",
            )
            assert_true(client_post_snapshot["player_count"] == 2, "Client should see both players after lobby reconnect.")
            assert_true(host_post_snapshot["player_count"] == 2, "Host should see both players after lobby reconnect.")

        failure_events = [
            event
            for reader in readers
            for event in reader.events
            if event.get("event") == "failure"
        ]
        assert_true(not failure_events, f"Child process reported failure events: {json.dumps(failure_events, sort_keys=True)}")

        print(f"Reconnect harness passed for scenario '{args.scenario}'.")
        print(f"Artifacts: {artifacts_dir}")
        print(f"Port: {port}")
        return 0
    except HarnessError as exc:
        print("Reconnect harness failed.", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        print(f"Artifacts: {artifacts_dir}", file=sys.stderr)
        print("Last events:", file=sys.stderr)
        print(summarize_last_events(readers), file=sys.stderr)
        return 1
    finally:
        terminate_processes(processes)


if __name__ == "__main__":
    raise SystemExit(main())
