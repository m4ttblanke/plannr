"""add session_token to google_credentials

Adds the opaque per-user bearer token that authenticates every per-user API
request. Nullable so the migration is safe on existing rows; those users are
forced to sign in again (which populates the column) the first time a protected
endpoint returns 401.

Revision ID: 92c09a31fa6e
Revises: caa17491fbb4
Create Date: 2026-09-03

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '92c09a31fa6e'
down_revision: Union[str, Sequence[str], None] = 'caa17491fbb4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'google_credentials',
        sa.Column('session_token', sa.Text(), nullable=True),
    )
    op.create_unique_constraint(
        'uq_google_credentials_session_token',
        'google_credentials',
        ['session_token'],
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint(
        'uq_google_credentials_session_token',
        'google_credentials',
        type_='unique',
    )
    op.drop_column('google_credentials', 'session_token')
