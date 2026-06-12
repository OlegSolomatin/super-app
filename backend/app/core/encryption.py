"""Encryption utilities for API keys using Fernet symmetric encryption.

Uses the app's SECRET_KEY (hashed to 32 bytes) as the encryption key.
"""

from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet

from app.core.config import settings


def _get_fernet() -> Fernet:
    """Derive a Fernet key from the app's SECRET_KEY."""
    # Fernet needs a 32-byte URL-safe base64 key
    key = hashlib.sha256(settings.SECRET_KEY.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(key))


def encrypt_api_key(plain_text: str) -> str:
    """Encrypt an API key or secret.

    Args:
        plain_text: The raw API key or secret string.

    Returns:
        Encrypted string (URL-safe base64).
    """
    f = _get_fernet()
    return f.encrypt(plain_text.encode()).decode()


def decrypt_api_key(encrypted: str) -> str:
    """Decrypt an encrypted API key or secret.

    Args:
        encrypted: The encrypted string (from DB).

    Returns:
        Original plain-text API key or secret.
    """
    f = _get_fernet()
    return f.decrypt(encrypted.encode()).decode()
