"""Optional backend-plugin registry.

The chat/recovery core must boot without any tenant-specific module.  Optional
features are therefore declared here and are enabled only through
``ANTIQ_BACKEND_PLUGINS``.  A bad plugin name fails at startup instead of
silently changing authorization behaviour.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from importlib import import_module
from typing import Iterable

from django.core.exceptions import ImproperlyConfigured
from django.urls import include, path


@dataclass(frozen=True)
class BackendPlugin:
    name: str
    app_config: str
    url_prefix: str
    urlconf: str


# Tenant policies, including RBAC, live outside the transport/recovery core.
# The module is intentionally disabled by default.
_KNOWN_PLUGINS: dict[str, BackendPlugin] = {
    'rbac': BackendPlugin(
        name='rbac',
        app_config='backend_plugins.rbac.apps.RbacPluginConfig',
        url_prefix='api/rbac/',
        urlconf='backend_plugins.rbac.urls',
    ),
    'task_kpi': BackendPlugin(
        name='task_kpi',
        app_config='backend_plugins.task_kpi.apps.TaskKpiPluginConfig',
        url_prefix='api/task-kpi/',
        urlconf='backend_plugins.task_kpi.urls',
    ),
}


def enabled_plugin_names(raw_value: str | None = None) -> tuple[str, ...]:
    raw_value = (
        os.environ.get('ANTIQ_BACKEND_PLUGINS', '')
        if raw_value is None
        else raw_value
    )
    names = tuple(
        name.strip().lower()
        for name in raw_value.split(',')
        if name.strip()
    )
    unknown = sorted(set(names).difference(_KNOWN_PLUGINS))
    if unknown:
        raise ImproperlyConfigured(
            'Unknown optional backend plugin(s): ' + ', '.join(unknown)
        )
    return names


def enabled_plugin_app_configs() -> list[str]:
    return [_KNOWN_PLUGINS[name].app_config for name in enabled_plugin_names()]


def plugin_urlpatterns() -> Iterable:
    for name in enabled_plugin_names():
        plugin = _KNOWN_PLUGINS[name]
        # Import only after the plugin was explicitly enabled. Core deployments
        # neither import nor migrate tenant-policy code.
        import_module(plugin.urlconf)
        yield path(plugin.url_prefix, include(plugin.urlconf))
