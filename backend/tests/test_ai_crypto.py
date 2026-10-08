import pytest
from app.ai.crypto import encrypt_secret, decrypt_secret, mask_secret

def test_crypto_roundtrip():
    secret = "sk-proj-1234567890abcdefghijklmnopqrstuvwxyz"
    encrypted = encrypt_secret(secret)
    assert encrypted != secret
    assert encrypted.startswith("enc:v1:")
    
    decrypted = decrypt_secret(encrypted)
    assert decrypted == secret

def test_crypto_idempotency_and_none():
    assert encrypt_secret(None) is None
    assert encrypt_secret("") is None
    assert decrypt_secret(None) is None
    assert decrypt_secret("") is None
    
    # Non cifra due volte se già enc:v1:
    encrypted = encrypt_secret("my-secret")
    assert encrypt_secret(encrypted) == encrypted

def test_crypto_legacy_plaintext_passthrough():
    legacy = "legacy-plain-key-123"
    assert decrypt_secret(legacy) == legacy

def test_mask_secret():
    assert mask_secret(None) is None
    assert mask_secret("") is None
    assert mask_secret("short") == "***"
    assert mask_secret("12345678") == "***"
    assert mask_secret("123456789") == "1234...6789"
    assert mask_secret("sk-proj-abc12345xyz6789") == "sk-proj...6789"
