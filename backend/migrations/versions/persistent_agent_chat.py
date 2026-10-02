"""Public chat history and one primary chat per user; retain all legacy IDs.

Revision ID: a261002_chat
Revises: a261002_categories
"""
from alembic import op
import sqlalchemy as sa

revision = "a261002_chat"
down_revision = "a261002_categories"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("conversation", sa.Column("is_primary", sa.Boolean(), nullable=False,
                                           server_default=sa.false()))
    # Existing rows cannot establish whether older checkpoints lost messages.
    op.add_column("conversation", sa.Column("history_complete", sa.Boolean(), nullable=False,
                                           server_default=sa.false()))
    op.create_index("uq_conversation_primary_user", "conversation", ["user_id"], unique=True,
                    postgresql_where=sa.text("is_primary"))


def downgrade():
    op.drop_index("uq_conversation_primary_user", table_name="conversation")
    op.drop_column("conversation", "history_complete")
    op.drop_column("conversation", "is_primary")
