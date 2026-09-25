"""Cross-process, session-scoped locks on a dedicated direct connection."""
from contextlib import asynccontextmanager
from hashlib import sha256

from psycopg import AsyncConnection

from app.agents.persistence import get_agent_persistence_settings


class ConversationBusy(Exception):
    pass


@asynccontextmanager
async def conversation_lock(user_id, conversation_id):
    key = int.from_bytes(sha256(f"sayfridge:agent:{user_id}:{conversation_id}".encode()).digest()[:8], "big", signed=True)
    settings = get_agent_persistence_settings()
    async with await AsyncConnection.connect(settings.psycopg_url(), autocommit=True, connect_timeout=10) as connection:
        row = await (await connection.execute("SELECT pg_try_advisory_lock(%s)", (key,))).fetchone()
        if not row[0]:
            raise ConversationBusy()
        try:
            yield
        finally:
            # Closing the dedicated connection also releases the lock on cancellation.
            if not connection.closed:
                await connection.execute("SELECT pg_advisory_unlock(%s)", (key,))
