"""add beta_purchasers backstop table

Local record of paid TestFlight beta purchases, written best-effort from the
Stripe webhook. Stripe remains the source of truth; this table exists so the
launch-time "3 months free" offer can be fulfilled even if Stripe data is later
unavailable.

Revision ID: b7f3c1a9d2e4
Revises: 92c09a31fa6e
Create Date: 2026-09-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'b7f3c1a9d2e4'
down_revision: Union[str, Sequence[str], None] = '92c09a31fa6e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'beta_purchasers',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('stripe_session_id', sa.Text(), nullable=False),
        sa.Column('email', sa.Text(), nullable=True),
        sa.Column('amount_total', sa.Integer(), nullable=True),
        sa.Column('currency', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('stripe_session_id', name='uq_beta_purchasers_stripe_session_id'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('beta_purchasers')
