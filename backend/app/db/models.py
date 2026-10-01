from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.db.base import Base


def uuid_primary_key() -> Mapped[uuid.UUID]:
    """Generate UUIDs in Python to avoid requiring database extensions."""

    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


def created_at_column() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


def updated_at_column() -> Mapped[datetime]:
    return mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class User(Base):
    __tablename__ = "user"
    __table_args__ = (
        UniqueConstraint("email", name="uq_user_email"),
        CheckConstraint("voice_limit_seconds >= 0", name="voice_limit_nonnegative"),
        CheckConstraint("voice_used_seconds >= 0", name="voice_used_nonnegative"),
        CheckConstraint("role IN ('USER', 'ADMIN')", name="role_allowed"),
        CheckConstraint(
            "status IN ('ACTIVE', 'SUSPENDED', 'DISABLED')",
            name="status_allowed",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    auth_provider: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default="LOCAL"
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False, server_default="USER")
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default="ACTIVE"
    )
    voice_limit_seconds: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0"
    )
    voice_used_seconds: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0"
    )
    voice_quota_reset_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    storage_spaces: Mapped[list[StorageSpace]] = relationship(back_populates="user")
    private_item_definitions: Mapped[list[ItemDefinition]] = relationship(
        back_populates="owner"
    )
    conversations: Mapped[list[Conversation]] = relationship(back_populates="user")


class StorageSpace(Base):
    __tablename__ = "storage_space"
    __table_args__ = (
        CheckConstraint("NOT is_default OR status = 'ACTIVE'", name="default_space_active"),
        Index("uq_storage_space_user_default", "user_id", unique=True,
              postgresql_where=text("is_default")),
        CheckConstraint(
            "type IN ('FRIDGE', 'FREEZER', 'PANTRY', 'WAREHOUSE', 'OTHER')",
            name="type_allowed",
        ),
        CheckConstraint("status IN ('ACTIVE', 'ARCHIVED')", name="status_allowed"),
        Index("ix_storage_space_user_status", "user_id", "status"),
        # Enforce unique names only for active spaces; allow names to be reused after archival.
        Index(
            "uq_storage_space_active_user_name",
            "user_id",
            func.lower(text("name")),
            unique=True,
            postgresql_where=text("status = 'ACTIVE'"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"), default=False)
    type: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default="ACTIVE"
    )
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    user: Mapped[User] = relationship(back_populates="storage_spaces")
    inventory_items: Mapped[list[InventoryItem]] = relationship(
        back_populates="storage_space"
    )


class ItemCategory(Base):
    __tablename__ = "item_category"
    __table_args__ = (
        UniqueConstraint("normalized_name", name="uq_item_category_normalized_name"),
        CheckConstraint("status IN ('ACTIVE', 'ARCHIVED')", name="status_allowed"),
        CheckConstraint("sort_order >= 0", name="sort_order_nonnegative"),
        Index("ix_item_category_status_sort", "status", "sort_order"),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(100), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default="ACTIVE"
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    item_definitions: Mapped[list[ItemDefinition]] = relationship(
        back_populates="category"
    )


class ItemDefinition(Base):
    __tablename__ = "item_definition"
    __table_args__ = (
        CheckConstraint("status IN ('ACTIVE', 'ARCHIVED')", name="status_allowed"),
        # Separate PostgreSQL partial unique indexes constrain the public dictionary and each user's private dictionary.
        Index(
            "uq_item_definition_public_name",
            "normalized_name",
            unique=True,
            postgresql_where=text("owner_user_id IS NULL"),
        ),
        Index(
            "uq_item_definition_private_owner_name",
            "owner_user_id",
            "normalized_name",
            unique=True,
            postgresql_where=text("owner_user_id IS NOT NULL"),
        ),
        Index("ix_item_definition_category_status", "category_id", "status"),
        Index("ix_item_definition_owner_status", "owner_user_id", "status"),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(100), nullable=False)
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("item_category.id", ondelete="RESTRICT"),
        nullable=False,
    )
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id", ondelete="CASCADE")
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default="ACTIVE"
    )
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    category: Mapped[ItemCategory] = relationship(back_populates="item_definitions")
    owner: Mapped[User | None] = relationship(back_populates="private_item_definitions")
    inventory_items: Mapped[list[InventoryItem]] = relationship(
        back_populates="item_definition"
    )


class InventoryItem(Base):
    __tablename__ = "inventory_item"
    __table_args__ = (
        CheckConstraint(
            "status IN ('IN_STOCK', 'EMPTY', 'DISCARDED', 'ARCHIVED')",
            name="status_allowed",
        ),
        CheckConstraint(
            "initial_amount >= 0 AND confirmed_current_amount >= 0 "
            "AND (estimated_current_amount IS NULL OR estimated_current_amount >= 0)",
            name="nonnegative_amounts",
        ),
        CheckConstraint(
            "(estimated_current_amount IS NULL AND estimated_current_unit IS NULL "
            "AND estimated_at IS NULL) OR "
            "(estimated_current_amount IS NOT NULL AND estimated_current_unit IS NOT NULL "
            "AND estimated_at IS NOT NULL)",
            name="estimate_trio",
        ),
        CheckConstraint("version >= 1", name="version_positive"),
        Index("ix_inventory_item_storage_status", "storage_space_id", "status"),
        Index("ix_inventory_item_definition", "item_definition_id"),
        Index(
            "ix_inventory_item_storage_status_expiry",
            "storage_space_id",
            "status",
            "expiry_date",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    storage_space_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("storage_space.id", ondelete="RESTRICT"),
        nullable=False,
    )
    item_definition_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("item_definition.id", ondelete="RESTRICT"),
        nullable=False,
    )
    notes: Mapped[str | None] = mapped_column(Text)
    purchase_date: Mapped[date | None] = mapped_column(Date)
    expiry_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default="IN_STOCK"
    )
    initial_amount: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    initial_unit: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_current_amount: Mapped[Decimal] = mapped_column(
        Numeric(12, 3), nullable=False
    )
    confirmed_current_unit: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    estimated_current_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    estimated_current_unit: Mapped[str | None] = mapped_column(String(16))
    estimated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    storage_space: Mapped[StorageSpace] = relationship(back_populates="inventory_items")
    item_definition: Mapped[ItemDefinition] = relationship(back_populates="inventory_items")
    operations: Mapped[list[InventoryOperation]] = relationship(
        back_populates="inventory_item"
    )


class InventoryOperation(Base):
    __tablename__ = "inventory_operation"
    __table_args__ = (
        UniqueConstraint("idempotency_key", name="uq_inventory_operation_idempotency_key"),
        CheckConstraint(
            "operation_type IN ('ADD', 'CONSUME', 'RECONCILE')",
            name="operation_type_allowed",
        ),
        CheckConstraint(
            "affects_state IN ('CONFIRMED', 'ESTIMATED')",
            name="affects_state_allowed",
        ),
        CheckConstraint(
            "input_method IN ('TEXT', 'VOICE', 'PHOTO', 'RECEIPT', 'MANUAL')",
            name="input_method_allowed",
        ),
        CheckConstraint(
            "quantity_kind IN ('AMOUNT', 'FRACTION', 'QUALITATIVE')",
            name="quantity_kind_allowed",
        ),
        CheckConstraint(
            "calculation_method IN ('EXACT', 'CONVERTED', 'AI_ESTIMATED')",
            name="calculation_method_allowed",
        ),
        CheckConstraint(
            "status IN ('PENDING_CONFIRMATION', 'SUCCESS', 'FAILED', 'UNDONE')",
            name="status_allowed",
        ),
        CheckConstraint(
            "(applied_change_amount IS NULL AND applied_change_unit IS NULL) OR "
            "(applied_change_amount IS NOT NULL AND applied_change_unit IS NOT NULL)",
            name="applied_change_pair",
        ),
        CheckConstraint(
            "applied_change_amount IS NULL OR applied_change_amount >= 0",
            name="applied_change_nonnegative",
        ),
        CheckConstraint(
            "(status = 'UNDONE' AND undone_at IS NOT NULL) OR "
            "(status <> 'UNDONE' AND undone_at IS NULL)",
            name="undone_timestamp_matches_status",
        ),
        Index("ix_inventory_operation_item_created", "inventory_item_id", "created_at"),
        Index("ix_inventory_operation_item_status", "inventory_item_id", "status"),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    inventory_item_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("inventory_item.id", ondelete="RESTRICT"),
        nullable=False,
    )
    operation_type: Mapped[str] = mapped_column(String(24), nullable=False)
    affects_state: Mapped[str] = mapped_column(String(24), nullable=False)
    input_method: Mapped[str] = mapped_column(String(16), nullable=False)
    quantity_kind: Mapped[str] = mapped_column(String(24), nullable=False)
    quantity_value: Mapped[str] = mapped_column(String(32), nullable=False)
    quantity_unit: Mapped[str | None] = mapped_column(String(16))
    calculation_method: Mapped[str] = mapped_column(String(24), nullable=False)
    applied_change_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    applied_change_unit: Mapped[str | None] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()
    undone_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    inventory_item: Mapped[InventoryItem] = relationship(back_populates="operations")


class AgentInventoryAction(Base):
    """A committed business receipt, independent of LangGraph checkpoints."""
    __tablename__ = "agent_inventory_action"
    id: Mapped[uuid.UUID] = uuid_primary_key()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    turn_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    action: Mapped[str] = mapped_column(String(24), nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    request_snapshot: Mapped[dict] = mapped_column(JSONB, nullable=False)
    result_snapshot: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = created_at_column()


class Conversation(Base):
    __tablename__ = "conversation"
    __table_args__ = (
        Index(
            "ix_conversation_user_updated_desc",
            "user_id",
            text("updated_at DESC"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    title: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = created_at_column()
    updated_at: Mapped[datetime] = updated_at_column()

    user: Mapped[User] = relationship(back_populates="conversations")
    messages: Mapped[list[ConversationMessage]] = relationship(
        back_populates="conversation"
    )


class ConversationMessage(Base):
    __tablename__ = "conversation_message"
    __table_args__ = (
        CheckConstraint("role IN ('USER', 'ASSISTANT')", name="role_allowed"),
        Index(
            "ix_conversation_message_order",
            "conversation_id",
            "created_at",
            "id",
        ),
    )

    id: Mapped[uuid.UUID] = uuid_primary_key()
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversation.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = created_at_column()

    conversation: Mapped[Conversation] = relationship(back_populates="messages")


class AuthSession(Base):
    """A revocable device session with sliding idle and absolute expiry."""
    __tablename__ = "auth_session"
    id: Mapped[uuid.UUID] = uuid_primary_key()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    absolute_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at_column()


class RefreshCredential(Base):
    """Only SHA-256 hashes are stored; consumed credentials detect replay."""
    __tablename__ = "auth_refresh_credential"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("auth_session.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
