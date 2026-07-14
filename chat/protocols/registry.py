import os

from . import v2, v3


def protocol_prefixes():
    """Return all formats this deployment can read.

    The V3 test deployment opts into V3 writes with an environment variable;
    the default remains V2 so an ordinary production process is unchanged.
    """
    return {
        'private_message_prefixes': [*v2.PRIVATE_PREFIXES, *v3.PRIVATE_PREFIXES],
        'group_message_prefixes': [*v2.GROUP_PREFIXES, *v3.GROUP_PREFIXES],
    }


def get_protocol_capabilities():
    mode = os.getenv('CRYPTO_PROTOCOL_MODE', 'v2').strip().lower()
    v3_enabled = mode in {'v3', 'v3_test', 'v3-test'}
    return {
        'protocol_version': 3 if v3_enabled else 2,
        'readable_private_message_prefixes': [*v2.PRIVATE_PREFIXES, *v3.PRIVATE_PREFIXES],
        'readable_group_message_prefixes': [*v2.GROUP_PREFIXES, *v3.GROUP_PREFIXES],
        'private_message_prefixes': [*v2.PRIVATE_PREFIXES, *v3.PRIVATE_PREFIXES]
        if v3_enabled else list(v2.PRIVATE_PREFIXES),
        'group_message_prefixes': [*v2.GROUP_PREFIXES, *v3.GROUP_PREFIXES]
        if v3_enabled else list(v2.GROUP_PREFIXES),
        'attachment_cipher_versions': [*v2.ATTACHMENT_CIPHER_VERSIONS, *v3.ATTACHMENT_CIPHER_VERSIONS]
        if v3_enabled else list(v2.ATTACHMENT_CIPHER_VERSIONS),
        'backup_schema_revision': v3.BACKUP_SCHEMA_REVISION if v3_enabled else v2.BACKUP_SCHEMA_REVISION,
        'minimum_decoder_version': '2.0.0',
        'active_writer': 'v3' if v3_enabled else 'v2',
    }
