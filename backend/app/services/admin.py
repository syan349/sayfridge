"""Administrator account queries and user-state transactions."""
from uuid import UUID

from sqlalchemy import func, select, true
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import User
from app.schemas.admin import AdminUserRead


class AdminError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _select_admin_users():
    return select(
        User.id,
        User.email,
        User.role,
        User.status,
        User.created_at,
        User.updated_at,
    )


def _read_user(row) -> AdminUserRead:
    return AdminUserRead(**dict(row))


async def list_users(session: AsyncSession, **query):
    statement = _select_admin_users()
    if query["q"]:
        statement = statement.where(User.email.icontains(query["q"], autoescape=True))
    for key, column in (("role", User.role), ("status", User.status)):
        if query[key] != "ALL":
            statement = statement.where(column == query[key])

    filtered = statement.cte("filtered_admin_users")
    total = select(func.count().label("total")).select_from(filtered).subquery()
    page = (
        select(filtered)
        .order_by(filtered.c.created_at.desc(), filtered.c.id.desc())
        .offset(min((query["page"] - 1) * query["page_size"], 2**63 - 1))
        .limit(query["page_size"])
        .subquery()
    )
    rows = (await session.execute(
        select(page, total.c.total)
        .select_from(total)
        .outerjoin(page, true())
        .order_by(page.c.created_at.desc(), page.c.id.desc())
    )).mappings().all()
    return [_read_user(row) for row in rows if row["id"] is not None], rows[0]["total"]


async def get_user(session: AsyncSession, user_id: UUID) -> AdminUserRead:
    row = (await session.execute(
        _select_admin_users().where(User.id == user_id)
    )).mappings().one_or_none()
    if row is None:
        raise AdminError("NOT_FOUND", "User not found")
    return _read_user(row)


async def update_user_status(
    session: AsyncSession,
    user_id: UUID,
    *,
    target_status: str,
) -> AdminUserRead:
    try:
        user = (await session.execute(
            select(User)
            .where(User.id == user_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if user is None:
            raise AdminError("NOT_FOUND", "User not found")
        if user.role != "USER":
            raise AdminError(
                "ADMIN_TARGET_FORBIDDEN",
                "Administrator accounts cannot be changed by this endpoint",
            )
        if user.status != target_status:
            user.status = target_status
        await session.flush()
        await session.refresh(user)
        result = AdminUserRead.model_validate(user)
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise
