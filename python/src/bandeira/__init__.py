"""
Bandeira Python SDK.

Polls the Bandeira server, caches flags locally, and evaluates strategies
in-process — so is_enabled() calls are pure in-memory lookups.
"""

from __future__ import annotations

import struct
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

import httpx

__all__ = ["BandeiraClient", "Context", "Config"]


@dataclass
class Config:
    """Configuration for the Bandeira client."""

    url: str
    """Base URL of the Bandeira server (e.g. "http://localhost:8080")."""

    token: str
    """Client API token (created in the Bandeira admin UI)."""

    poll_interval: float = 15.0
    """Poll interval in seconds. Defaults to 15."""

    streaming: bool = False
    """Enable real-time flag updates via SSE instead of polling."""

    http_client: httpx.Client | None = None
    """Optional custom httpx client."""


@dataclass
class Context:
    """Runtime context for strategy evaluation."""

    user_id: str = ""
    session_id: str = ""
    remote_address: str = ""
    properties: dict[str, str] = field(default_factory=dict)


@dataclass
class _Constraint:
    context_name: str
    operator: str
    values: list[str]
    inverted: bool = False
    case_insensitive: bool = False


@dataclass
class _Strategy:
    name: str
    parameters: dict[str, Any] = field(default_factory=dict)
    constraints: list[_Constraint] = field(default_factory=list)


@dataclass
class _Flag:
    name: str
    enabled: bool
    strategies: list[_Strategy] = field(default_factory=list)


class BandeiraClient:
    """Bandeira feature flag client. Thread-safe."""

    def __init__(self, config: Config) -> None:
        if not config.url:
            raise ValueError("bandeira: url is required")
        if not config.token:
            raise ValueError("bandeira: token is required")

        self._url = config.url.rstrip("/")
        self._token = config.token
        self._poll_interval = config.poll_interval
        self._http = config.http_client or httpx.Client(timeout=10.0)
        self._owns_http = config.http_client is None

        self._streaming = config.streaming
        self._lock = threading.RLock()
        self._flags: dict[str, _Flag] = {}
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        """Fetch flags and start the background poller or SSE stream."""
        self._fetch()
        if self._streaming:
            self._thread = threading.Thread(target=self._stream, daemon=True)
        else:
            self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()

    def close(self) -> None:
        """Stop the background poller and release resources."""
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=5.0)
        if self._owns_http:
            self._http.close()

    def is_enabled(self, name: str, ctx: Context | None = None) -> bool:
        """
        Returns True if the flag is enabled.

        Without context, only the enabled/disabled state is checked.
        """
        with self._lock:
            flag = self._flags.get(name)

        if flag is None or not flag.enabled:
            return False

        if not flag.strategies:
            return True

        eval_ctx = ctx or Context()

        # OR logic — if ANY strategy returns true, flag is ON.
        for s in flag.strategies:
            if _evaluate_strategy(s, eval_ctx):
                return True

        return False

    def all_flags(self) -> dict[str, bool]:
        """Returns a snapshot of all known flags and their enabled state."""
        with self._lock:
            return {k: v.enabled for k, v in self._flags.items()}

    def load_flags(self, response: dict[str, Any]) -> None:
        """Load flags from an API response dict (useful for testing)."""
        flags = _parse_response(response)
        with self._lock:
            self._flags = flags

    def _poll(self) -> None:
        while not self._stop_event.wait(self._poll_interval):
            try:
                self._fetch()
            except Exception:
                pass

    def _stream(self) -> None:
        url = f"{self._url}/api/v1/stream"
        headers = {
            "Authorization": f"Bearer {self._token}",
            "Accept": "text/event-stream",
        }
        backoff = 1.0
        max_backoff = 30.0

        while not self._stop_event.is_set():
            try:
                with httpx.Client(timeout=None) as client:
                    with client.stream("GET", url, headers=headers) as resp:
                        resp.raise_for_status()
                        backoff = 1.0  # Reset on successful connection.
                        event_type = ""
                        data_lines: list[str] = []

                        for line in resp.iter_lines():
                            if self._stop_event.is_set():
                                return
                            if line.startswith(":"):
                                continue
                            if line.startswith("event:"):
                                event_type = line[6:].strip()
                            elif line.startswith("data:"):
                                data_lines.append(line[5:].strip())
                            elif line == "":
                                if event_type == "flags" and data_lines:
                                    try:
                                        import json

                                        data = json.loads("\n".join(data_lines))
                                        flags = _parse_response(data)
                                        with self._lock:
                                            self._flags = flags
                                    except Exception:
                                        pass
                                event_type = ""
                                data_lines = []
            except Exception:
                pass

            if self._stop_event.is_set():
                return
            self._stop_event.wait(backoff)
            backoff = min(backoff * 2, max_backoff)

    def _fetch(self) -> None:
        url = f"{self._url}/api/v1/flags"
        resp = self._http.get(
            url, headers={"Authorization": f"Bearer {self._token}"}
        )
        resp.raise_for_status()
        data = resp.json()
        flags = _parse_response(data)
        with self._lock:
            self._flags = flags


def _parse_response(data: dict[str, Any]) -> dict[str, _Flag]:
    flags: dict[str, _Flag] = {}
    for f in data.get("flags", []):
        strategies = []
        for s in f.get("strategies", []):
            constraints = [
                _Constraint(
                    context_name=c.get("context_name", ""),
                    operator=c.get("operator", ""),
                    values=c.get("values", []),
                    inverted=c.get("inverted", False),
                    case_insensitive=c.get("case_insensitive", False),
                )
                for c in s.get("constraints", [])
            ]
            strategies.append(
                _Strategy(
                    name=s.get("name", ""),
                    parameters=s.get("parameters", {}),
                    constraints=constraints,
                )
            )
        flags[f["name"]] = _Flag(
            name=f["name"],
            enabled=f.get("enabled", False),
            strategies=strategies,
        )
    return flags


# ── Strategy evaluation ────────────────────────────────────────────────────


def _evaluate_strategy(s: _Strategy, ctx: Context) -> bool:
    # AND logic — all constraints must pass.
    for con in s.constraints:
        if not _evaluate_constraint(con, ctx):
            return False

    match s.name:
        case "default":
            return True
        case "userWithId":
            return _eval_user_with_id(s, ctx)
        case "gradualRollout":
            return _eval_gradual_rollout(s, ctx)
        case "remoteAddress":
            return _eval_remote_address(s, ctx)
        case _:
            return True


def _eval_user_with_id(s: _Strategy, ctx: Context) -> bool:
    raw = s.parameters.get("userIds")
    if not isinstance(raw, str):
        return False
    return ctx.user_id in _split_multi(raw)


def _eval_gradual_rollout(s: _Strategy, ctx: Context) -> bool:
    rollout_raw = s.parameters.get("rollout")
    if isinstance(rollout_raw, (int, float)):
        rollout = int(rollout_raw)
    elif isinstance(rollout_raw, str):
        try:
            rollout = int(rollout_raw)
        except ValueError:
            return False
    else:
        return False

    if rollout >= 100:
        return True
    if rollout <= 0:
        return False

    stickiness = s.parameters.get("stickiness", "userId")
    if not isinstance(stickiness, str):
        stickiness = "userId"

    match stickiness:
        case "userId":
            stickiness_value = ctx.user_id
        case "sessionId":
            stickiness_value = ctx.session_id
        case _:
            stickiness_value = ctx.properties.get(stickiness, "")

    if not stickiness_value:
        return False

    group_id = s.parameters.get("groupId", "")
    if not isinstance(group_id, str):
        group_id = ""

    normalized = _normalized_hash(stickiness_value + group_id)
    return normalized < rollout


def _eval_remote_address(s: _Strategy, ctx: Context) -> bool:
    raw = s.parameters.get("ips") or s.parameters.get("IPs")
    if not isinstance(raw, str):
        return False

    addr = ctx.remote_address
    for entry in _split_multi(raw):
        if entry == addr:
            return True
        if entry.endswith(".") and addr.startswith(entry):
            return True
    return False


# ── Constraint evaluation ──────────────────────────────────────────────────


def _evaluate_constraint(con: _Constraint, ctx: Context) -> bool:
    ctx_value = _get_context_value(con.context_name, ctx)
    result = _eval_operator(con.operator, ctx_value, con.values, con.case_insensitive)
    return not result if con.inverted else result


def _get_context_value(name: str, ctx: Context) -> str:
    match name:
        case "userId":
            return ctx.user_id
        case "sessionId":
            return ctx.session_id
        case "remoteAddress":
            return ctx.remote_address
        case _:
            return ctx.properties.get(name, "")


def _eval_operator(
    op: str, ctx_value: str, values: list[str], case_insensitive: bool
) -> bool:
    cv = ctx_value.lower() if case_insensitive else ctx_value

    def norm(v: str) -> str:
        return v.lower() if case_insensitive else v

    match op:
        case "IN":
            return any(cv == norm(v) for v in values)
        case "NOT_IN":
            return all(cv != norm(v) for v in values)
        case "STR_CONTAINS":
            return any(norm(v) in cv for v in values)
        case "STR_STARTS_WITH":
            return any(cv.startswith(norm(v)) for v in values)
        case "STR_ENDS_WITH":
            return any(cv.endswith(norm(v)) for v in values)
        case "NUM_EQ" | "NUM_GT" | "NUM_GTE" | "NUM_LT" | "NUM_LTE":
            try:
                num = float(cv)
            except ValueError:
                return False
            for v in values:
                try:
                    target = float(v)
                except ValueError:
                    continue
                match op:
                    case "NUM_EQ":
                        if num == target:
                            return True
                    case "NUM_GT":
                        if num > target:
                            return True
                    case "NUM_GTE":
                        if num >= target:
                            return True
                    case "NUM_LT":
                        if num < target:
                            return True
                    case "NUM_LTE":
                        if num <= target:
                            return True
            return False
        case "DATE_AFTER" | "DATE_BEFORE":
            try:
                t = datetime.fromisoformat(cv)
            except ValueError:
                return False
            for v in values:
                try:
                    target = datetime.fromisoformat(v)
                except ValueError:
                    continue
                if op == "DATE_AFTER" and t > target:
                    return True
                if op == "DATE_BEFORE" and t < target:
                    return True
            return False
        case _:
            return False


# ── Helpers ────────────────────────────────────────────────────────────────


def _split_multi(s: str) -> list[str]:
    """Split on commas and newlines, trim whitespace, drop empties."""
    s = s.replace("\r\n", ",").replace("\n", ",")
    return [p.strip() for p in s.split(",") if p.strip()]


def _normalized_hash(s: str) -> int:
    """FNV-1a 32-bit hash, mod 100. Matches the Go SDK implementation."""
    h = 0x811C9DC5  # FNV offset basis
    for byte in s.encode("utf-8"):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF  # FNV prime, keep 32-bit
    return h % 100
