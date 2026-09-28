"""Process-local protection against repeated login attempts.

This deliberately stores only hashed client/account keys. It is a small application
guardrail; deployments with multiple instances must also enforce a shared limit at
the ingress or gateway.
"""

from collections import deque
from dataclasses import dataclass
import hashlib
import math
from threading import Lock
import time


@dataclass(frozen=True)
class LoginAttemptDecision:
    allowed: bool
    retry_after_seconds: int = 0


class LoginRateLimiter:
    """Apply a sliding-window limit to one client/account pair."""

    _MAX_TRACKED_KEYS = 10_000

    def __init__(self) -> None:
        self._attempts: dict[str, deque[float]] = {}
        self._lock = Lock()

    @staticmethod
    def key(client_host: str, normalized_email: str) -> str:
        value = f"{client_host}\0{normalized_email}".encode("utf-8")
        return hashlib.sha256(value).hexdigest()

    def reserve(
        self,
        key: str,
        *,
        maximum_attempts: int,
        window_seconds: int,
        now: float | None = None,
    ) -> LoginAttemptDecision:
        """Reserve one attempt atomically, rejecting attempts beyond the window limit."""

        current = time.monotonic() if now is None else now
        cutoff = current - window_seconds
        with self._lock:
            if key not in self._attempts and len(self._attempts) >= self._MAX_TRACKED_KEYS:
                stale = [
                    tracked_key
                    for tracked_key, values in self._attempts.items()
                    if not values or values[-1] <= cutoff
                ]
                for tracked_key in stale:
                    self._attempts.pop(tracked_key, None)
                if len(self._attempts) >= self._MAX_TRACKED_KEYS:
                    oldest_key = min(
                        self._attempts,
                        key=lambda tracked_key: self._attempts[tracked_key][-1],
                    )
                    self._attempts.pop(oldest_key)
            attempts = self._attempts.setdefault(key, deque())
            while attempts and attempts[0] <= cutoff:
                attempts.popleft()
            if len(attempts) >= maximum_attempts:
                retry_after = max(1, math.ceil(attempts[0] + window_seconds - current))
                return LoginAttemptDecision(False, retry_after)
            attempts.append(current)
            return LoginAttemptDecision(True)

    def clear(self, key: str) -> None:
        """Clear the window after successful authentication."""

        with self._lock:
            self._attempts.pop(key, None)


login_rate_limiter = LoginRateLimiter()
