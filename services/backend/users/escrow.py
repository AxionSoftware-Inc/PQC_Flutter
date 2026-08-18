"""Envelope encryption for enterprise recovery records.

KMS only wraps a 256-bit data-encryption key (DEK).  Recovery material is
encrypted with AES-256-GCM in the application process, so manifest size is not
limited by the 4 KiB KMS Encrypt API limit.
"""
from __future__ import annotations

import base64
import hashlib
import os
from dataclasses import dataclass

from cryptography.fernet import Fernet, InvalidToken
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured


@dataclass(frozen=True)
class EscrowEnvelope:
    encrypted_data_key: str
    ciphertext: str
    nonce: str
    key_id: str
    encryption_context: dict[str, str]


class KeyEscrowProvider:
    def encrypt(self, *, account_id: int, plaintext: str) -> EscrowEnvelope:
        raise NotImplementedError

    def decrypt(self, *, account_id: int, envelope: EscrowEnvelope) -> str:
        raise NotImplementedError

    @staticmethod
    def _context(account_id: int) -> dict[str, str]:
        return {'account_id': str(account_id), 'purpose': 'pqc-chat-recovery-v2'}

    @staticmethod
    def _seal(*, plaintext: str, data_key: bytes, context: dict[str, str]) -> tuple[str, str]:
        nonce = os.urandom(12)
        ciphertext = AESGCM(data_key).encrypt(nonce, plaintext.encode('utf-8'), str(sorted(context.items())).encode())
        return base64.b64encode(ciphertext).decode('ascii'), base64.b64encode(nonce).decode('ascii')

    @staticmethod
    def _open(*, envelope: EscrowEnvelope, data_key: bytes) -> str:
        return AESGCM(data_key).decrypt(
            base64.b64decode(envelope.nonce),
            base64.b64decode(envelope.ciphertext),
            str(sorted(envelope.encryption_context.items())).encode(),
        ).decode('utf-8')


class AwsKmsEscrowProvider(KeyEscrowProvider):
    def __init__(self, key_id: str):
        if not key_id:
            raise ImproperlyConfigured('AWS_KMS_ESCROW_KEY_ID is required.')
        try:
            import boto3
        except ImportError as error:  # pragma: no cover
            raise ImproperlyConfigured('boto3 is required for AWS KMS escrow.') from error
        self._key_id = key_id
        self._client = boto3.client('kms', region_name=settings.AWS_REGION or None)

    def encrypt(self, *, account_id: int, plaintext: str) -> EscrowEnvelope:
        context = self._context(account_id)
        response = self._client.generate_data_key(
            KeyId=self._key_id,
            KeySpec='AES_256',
            EncryptionContext=context,
        )
        plaintext_key = bytearray(response['Plaintext'])
        try:
            ciphertext, nonce = self._seal(
                plaintext=plaintext, data_key=bytes(plaintext_key), context=context,
            )
        finally:
            plaintext_key[:] = b'\x00' * len(plaintext_key)
        return EscrowEnvelope(
            encrypted_data_key=base64.b64encode(response['CiphertextBlob']).decode('ascii'),
            ciphertext=ciphertext,
            nonce=nonce,
            key_id=response.get('KeyId', self._key_id),
            encryption_context=context,
        )

    def decrypt(self, *, account_id: int, envelope: EscrowEnvelope) -> str:
        context = self._context(account_id)
        if envelope.encryption_context != context:
            raise PermissionError('Recovery escrow context mismatch.')
        response = self._client.decrypt(
            CiphertextBlob=base64.b64decode(envelope.encrypted_data_key),
            EncryptionContext=context,
            KeyId=envelope.key_id,
        )
        plaintext_key = bytearray(response['Plaintext'])
        try:
            try:
                return self._open(envelope=envelope, data_key=bytes(plaintext_key))
            except InvalidTag as error:
                raise ValueError('Recovery escrow payload authentication failed.') from error
        finally:
            plaintext_key[:] = b'\x00' * len(plaintext_key)


class LocalDevelopmentEscrowProvider(KeyEscrowProvider):
    """Development-only equivalent; production selection is forbidden."""
    def _cipher(self) -> Fernet:
        seed = settings.LOCAL_ESCROW_TEST_SECRET.encode('utf-8')
        return Fernet(base64.urlsafe_b64encode(hashlib.sha256(seed).digest()))

    def encrypt(self, *, account_id: int, plaintext: str) -> EscrowEnvelope:
        context = self._context(account_id)
        data_key = bytearray(os.urandom(32))
        try:
            ciphertext, nonce = self._seal(plaintext=plaintext, data_key=bytes(data_key), context=context)
            wrapped = self._cipher().encrypt(bytes(data_key))
        finally:
            data_key[:] = b'\x00' * len(data_key)
        return EscrowEnvelope(base64.b64encode(wrapped).decode(), ciphertext, nonce, 'local-development', context)

    def decrypt(self, *, account_id: int, envelope: EscrowEnvelope) -> str:
        if envelope.encryption_context != self._context(account_id):
            raise PermissionError('Recovery escrow account mismatch.')
        try:
            data_key = bytearray(self._cipher().decrypt(base64.b64decode(envelope.encrypted_data_key)))
        except (InvalidToken, ValueError) as error:
            raise ValueError('Recovery escrow payload is corrupted.') from error
        try:
            try:
                return self._open(envelope=envelope, data_key=bytes(data_key))
            except InvalidTag as error:
                raise ValueError('Recovery escrow payload authentication failed.') from error
        finally:
            data_key[:] = b'\x00' * len(data_key)


def get_key_escrow_provider() -> KeyEscrowProvider:
    if settings.AWS_KMS_ESCROW_KEY_ID:
        return AwsKmsEscrowProvider(settings.AWS_KMS_ESCROW_KEY_ID)
    if settings.CRYPTO_ESCROW_REQUIRE_KMS:
        raise ImproperlyConfigured('AWS KMS escrow must be configured in production.')
    return LocalDevelopmentEscrowProvider()
