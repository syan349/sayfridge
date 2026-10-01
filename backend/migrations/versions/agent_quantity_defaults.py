"""Ensure one active default space per user.

Revision ID: a260929_defaults
Revises: 02ec95582dc7
"""
from alembic import op
import sqlalchemy as sa

revision = "a260929_defaults"
down_revision = "02ec95582dc7"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("storage_space", sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_check_constraint("default_space_active", "storage_space", "NOT is_default OR status = 'ACTIVE'")
    op.create_index("uq_storage_space_user_default", "storage_space", ["user_id"], unique=True,
                    postgresql_where=sa.text("is_default"))


def downgrade():
    op.drop_index("uq_storage_space_user_default", table_name="storage_space")
    op.drop_constraint("default_space_active", "storage_space", type_="check")
    op.drop_column("storage_space", "is_default")
