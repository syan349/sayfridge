"""Security audit records contain fixed event names and internal UUIDs only."""
import json
import logging
import uuid
from typing import Literal

from fastapi import Request

logger = logging.getLogger("app.security.audit")
Event = Literal[
    "authentication_denied", "admin_access_denied", "login_denied",
    "login_rate_limited", "login_succeeded", "refresh_denied",
    "refresh_replay_detected", "session_revoked", "password_changed",
    "password_change_denied", "password_change_rate_limited",
]


def request_correlation_id(request: Request) -> uuid.UUID:
    """Generate a server-owned ID; never copy arbitrary client headers into logs."""
    if not hasattr(request.state, "security_request_id"):
        request.state.security_request_id = uuid.uuid4()
    return request.state.security_request_id


def security_event(
    event: Event, *, request_id: uuid.UUID | None = None,
    user_id: uuid.UUID | None = None, session_id: uuid.UUID | None = None,
) -> None:
    record = {"event": event}
    for name, value in (("request_id", request_id), ("user_id", user_id), ("session_id", session_id)):
        if isinstance(value, uuid.UUID):
            record[name] = str(value)
    # No email, IP, credentials, hashes, exception text or request payload.
    level = logging.INFO if event in {"login_succeeded", "password_changed"} else logging.WARNING
    logger.log(level, json.dumps(record, sort_keys=True))
