"""API endpoints for exchange API key management.

GET    /exchange-keys          — List user's exchange keys
POST   /exchange-keys          — Add new exchange key
PUT    /exchange-keys/{id}     — Update exchange key
DELETE /exchange-keys/{id}     — Delete exchange key
POST   /exchange-keys/{id}/check  — Test key + fetch balance
"""

from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.core.encryption import decrypt_api_key, encrypt_api_key
from app.models.exchange_key import ExchangeKey
from app.models.user import User
from app.schemas.exchange_key import (
    ExchangeKeyCreate,
    ExchangeKeyListResponse,
    ExchangeKeyResponse,
    ExchangeKeyUpdate,
)
from app.services.exchange.balance_checker import (
    SUPPORTED_EXCHANGES,
    check_key_validity,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/exchange-keys", tags=["exchange"])


@router.get("", response_model=ExchangeKeyListResponse)
async def list_exchange_keys(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExchangeKeyListResponse:
    """List all exchange API keys for the current user."""
    stmt = (
        select(ExchangeKey)
        .where(ExchangeKey.user_id == current_user.id)
        .order_by(ExchangeKey.created_at.desc())
    )
    result = await session.execute(stmt)
    keys = result.scalars().all()

    return ExchangeKeyListResponse(
        items=[ExchangeKeyResponse.model_validate(k) for k in keys],
        total=len(keys),
    )


@router.post(
    "", response_model=ExchangeKeyResponse, status_code=status.HTTP_201_CREATED
)
async def create_exchange_key(
    body: ExchangeKeyCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExchangeKeyResponse:
    """Add a new exchange API key.

    The key and secret are encrypted at rest before saving.
    """
    exchange = body.exchange.lower().strip()

    if exchange not in SUPPORTED_EXCHANGES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Неподдерживаемая биржа: {exchange}. Поддерживаются: {', '.join(sorted(SUPPORTED_EXCHANGES))}.",
        )

    # Check for duplicate (same exchange)
    stmt = select(ExchangeKey).where(
        ExchangeKey.user_id == current_user.id,
        ExchangeKey.exchange == exchange,
        ExchangeKey.is_active == True,
    )
    result = await session.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Ключ для биржи {exchange} уже существует. Обновите его или удалите старый.",
        )

    # Encrypt key and secret
    encrypted_key = encrypt_api_key(body.api_key)
    encrypted_secret = encrypt_api_key(body.api_secret)
    encrypted_passphrase = (
        encrypt_api_key(body.passphrase) if body.passphrase else None
    )

    db_key = ExchangeKey(
        user_id=current_user.id,
        exchange=exchange,
        label=body.label or exchange.capitalize(),
        api_key_encrypted=encrypted_key,
        api_secret_encrypted=encrypted_secret,
        passphrase=encrypted_passphrase,
        status="untested",
        expires_at=body.expires_at,
    )
    session.add(db_key)
    await session.commit()
    await session.refresh(db_key)

    logger.info(
        "User %s added %s API key (id=%s)",
        current_user.id,
        exchange,
        db_key.id,
    )

    return ExchangeKeyResponse.model_validate(db_key)


@router.put("/{key_id}", response_model=ExchangeKeyResponse)
async def update_exchange_key(
    key_id: str,
    body: ExchangeKeyUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExchangeKeyResponse:
    """Update an existing exchange API key."""
    stmt = select(ExchangeKey).where(
        ExchangeKey.id == key_id, ExchangeKey.user_id == current_user.id
    )
    result = await session.execute(stmt)
    db_key = result.scalar_one_or_none()

    if db_key is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ключ не найден.",
        )

    # Update fields
    if body.label is not None:
        db_key.label = body.label
    if body.api_key is not None:
        db_key.api_key_encrypted = encrypt_api_key(body.api_key)
        db_key.status = "untested"
    if body.api_secret is not None:
        db_key.api_secret_encrypted = encrypt_api_key(body.api_secret)
        db_key.status = "untested"
    if body.passphrase is not None:
        db_key.passphrase = encrypt_api_key(body.passphrase)
    if body.is_active is not None:
        db_key.is_active = body.is_active

    await session.commit()
    await session.refresh(db_key)

    return ExchangeKeyResponse.model_validate(db_key)


@router.delete("/{key_id}", status_code=status.HTTP_200_OK)
async def delete_exchange_key(
    key_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Delete an exchange API key."""
    stmt = select(ExchangeKey).where(
        ExchangeKey.id == key_id, ExchangeKey.user_id == current_user.id
    )
    result = await session.execute(stmt)
    db_key = result.scalar_one_or_none()

    if db_key is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ключ не найден.",
        )

    await session.delete(db_key)
    await session.commit()

    logger.info("User %s deleted %s key (id=%s)", current_user.id, db_key.exchange, key_id)


@router.post("/{key_id}/check", response_model=ExchangeKeyResponse)
async def check_exchange_key(
    key_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExchangeKeyResponse:
    """Test the exchange key and fetch current balance."""
    stmt = select(ExchangeKey).where(
        ExchangeKey.id == key_id, ExchangeKey.user_id == current_user.id
    )
    result = await session.execute(stmt)
    db_key = result.scalar_one_or_none()

    if db_key is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ключ не найден.",
        )

    # Decrypt
    try:
        api_key = decrypt_api_key(db_key.api_key_encrypted)
        api_secret = decrypt_api_key(db_key.api_secret_encrypted)
        passphrase = (
            decrypt_api_key(db_key.passphrase) if db_key.passphrase else None
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка дешифрования ключа: {e}",
        )

    # Check validity
    from datetime import datetime, timezone

    is_valid, balance, error_msg = await check_key_validity(
        exchange=db_key.exchange,
        api_key=api_key,
        api_secret=api_secret,
        passphrase=passphrase,
    )

    db_key.status = "valid" if is_valid else "invalid"
    db_key.error_message = error_msg if not is_valid else None
    db_key.balance = balance
    db_key.balance_updated_at = datetime.now(timezone.utc)
    db_key.last_checked_at = datetime.now(timezone.utc)
    await session.commit()
    await session.refresh(db_key)

    logger.info(
        "Checked %s key (id=%s): %s (balance=$%s)",
        db_key.exchange,
        key_id,
        db_key.status,
        balance or "N/A",
    )

    return ExchangeKeyResponse.model_validate(db_key)
