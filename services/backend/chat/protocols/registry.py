import os

from . import v2, v3


def protocol_prefixes():
    """Return all formats this deployment can read.

    The V3 test deployment opts into V3 writes with an environment variable;
    the default remains V2 so an ordinary production process is unchanged.
    """
    return {
        'private_message_prefixes': list(v2.PRIVATE_PREFIXES),
        'group_message_prefixes': list(v2.GROUP_PREFIXES),
        'group_envelope_prefixes': [v2.GROUP_ENVELOPE_PREFIX],
    }


def get_protocol_capabilities():
    mode = os.getenv('CRYPTO_PROTOCOL_MODE', 'v2').strip().lower()
    v3_enabled = mode in {'v3', 'v3_test', 'v3-test', 'v3_full', 'v3-full'}
    v3_attachment_enabled = mode in {'v3_full', 'v3-full'}
    v25_enabled = mode in {'v25', 'v2.5', 'v2_5'}
    readable_message_private = [*v2.PRIVATE_PREFIXES]
    readable_message_group = [*v2.GROUP_PREFIXES]
    if v3_enabled:
        readable_message_private.extend(v3.PRIVATE_PREFIXES)
        readable_message_group.extend(v3.GROUP_PREFIXES)
    readable_group_envelopes = [v2.GROUP_ENVELOPE_PREFIX]
    writable_group_envelopes = [v2.GROUP_ENVELOPE_PREFIX]
    if v25_enabled:
        readable_group_envelopes.append(v2.GROUP_ENVELOPE_V25_PREFIX)
        writable_group_envelopes = [v2.GROUP_ENVELOPE_V25_PREFIX]
    return {
        'protocol_version': 3 if v3_enabled else 2,
        'readable_private_message_prefixes': readable_message_private,
        'readable_group_message_prefixes': readable_message_group,
        'private_message_prefixes': [*v2.PRIVATE_PREFIXES, *v3.PRIVATE_PREFIXES]
        if v3_enabled else list(v2.PRIVATE_PREFIXES),
        'group_message_prefixes': [*v2.GROUP_PREFIXES, *v3.GROUP_PREFIXES]
        if v3_enabled else list(v2.GROUP_PREFIXES),
        'readable_group_envelope_prefixes': readable_group_envelopes,
        'group_envelope_prefixes': writable_group_envelopes,
        'group_envelope_algorithms': {
            v2.GROUP_ENVELOPE_PREFIX: v2.GROUP_ENVELOPE_ALGORITHM,
            v2.GROUP_ENVELOPE_V25_PREFIX: v2.GROUP_ENVELOPE_V25_ALGORITHM,
        },
        'attachment_cipher_versions': [
            *v2.ATTACHMENT_CIPHER_VERSIONS,
            *v3.ATTACHMENT_CIPHER_VERSIONS,
        ] if v3_attachment_enabled else list(v2.ATTACHMENT_CIPHER_VERSIONS),
        # v1 remains readable for already stored direct uploads; new writers
        # use the advertised current version above.
        'readable_attachment_cipher_versions': [
            'attachment:v1',
            *v2.ATTACHMENT_CIPHER_VERSIONS,
            *v3.ATTACHMENT_CIPHER_VERSIONS,
        ] if v3_attachment_enabled else ['attachment:v1', *v2.ATTACHMENT_CIPHER_VERSIONS],
        'backup_schema_revision': v3.BACKUP_SCHEMA_REVISION if v3_enabled else v2.BACKUP_SCHEMA_REVISION,
        'minimum_decoder_version': '2.0.0',
        'active_writer': 'v3' if v3_enabled else 'v2',
        'active_group_envelope_writer': 'v2.5' if v25_enabled else 'v2',
    }
