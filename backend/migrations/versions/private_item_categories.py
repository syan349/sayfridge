"""User-owned categories and batch-specific category edits.

Revision ID: a261002_categories
Revises: a261001_sessions
"""
from alembic import op
import sqlalchemy as sa

revision = "a261002_categories"
down_revision = "a261001_sessions"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("item_category", sa.Column("owner_user_id", sa.UUID(), nullable=True))
    op.create_foreign_key("fk_item_category_owner", "item_category", "user", ["owner_user_id"], ["id"], ondelete="RESTRICT")
    op.drop_constraint("uq_item_category_normalized_name", "item_category", type_="unique")
    op.create_index("uq_item_category_public_name", "item_category", ["normalized_name"], unique=True,
                    postgresql_where=sa.text("owner_user_id IS NULL"))
    op.create_index("uq_item_category_private_owner_name", "item_category", ["owner_user_id", "normalized_name"], unique=True,
                    postgresql_where=sa.text("owner_user_id IS NOT NULL"))
    op.add_column("inventory_item", sa.Column("category_override_id", sa.UUID(), nullable=True))
    op.create_foreign_key("fk_inventory_category_override", "inventory_item", "item_category", ["category_override_id"], ["id"], ondelete="RESTRICT")


def downgrade():
    # A downgrade with private data requires explicit export/removal first.
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM item_category WHERE owner_user_id IS NOT NULL)
           OR EXISTS (SELECT 1 FROM inventory_item WHERE category_override_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Export/remove private categories and batch category overrides before downgrade';
        END IF;
    END $$;""")
    op.create_unique_constraint("uq_item_category_normalized_name", "item_category", ["normalized_name"])
    op.drop_constraint("fk_inventory_category_override", "inventory_item", type_="foreignkey")
    op.drop_column("inventory_item", "category_override_id")
    op.drop_index("uq_item_category_private_owner_name", table_name="item_category")
    op.drop_index("uq_item_category_public_name", table_name="item_category")
    op.drop_constraint("fk_item_category_owner", "item_category", type_="foreignkey")
    op.drop_column("item_category", "owner_user_id")
