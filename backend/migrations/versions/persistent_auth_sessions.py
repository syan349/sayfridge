"""Add revocable sessions and rotating refresh credentials.

Revision ID: a261001_sessions
Revises: a260929_defaults
"""
from alembic import op
import sqlalchemy as sa

revision = "a261001_sessions"
down_revision = "a260929_defaults"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("auth_session",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("absolute_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"))
    op.create_index("ix_auth_session_user_id", "auth_session", ["user_id"])
    op.create_table("auth_refresh_credential",
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("session_id", sa.UUID(), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["session_id"], ["auth_session.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("token_hash"))
    op.create_index("ix_auth_refresh_credential_session_id", "auth_refresh_credential", ["session_id"])


def downgrade():
    op.drop_table("auth_refresh_credential")
    op.drop_table("auth_session")
