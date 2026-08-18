"""Versioned wire-protocol contracts for the chat API.

Each engine adds a module here instead of editing the frozen contract of an
older engine. The registry is the only place the API advertises active
read/write capabilities.
"""

from .registry import get_protocol_capabilities, protocol_prefixes

__all__ = ['get_protocol_capabilities', 'protocol_prefixes']
