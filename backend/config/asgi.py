"""
ASGI config for config project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/6.0/howto/deployment/asgi/
"""

import os
import sys
from pathlib import Path

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application
from django.urls import path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

django_asgi_app = get_asgi_application()

from chat.consumers import ChatEventsConsumer

websocket_urlpatterns = [
    path('ws/chat', ChatEventsConsumer.as_asgi()),
    # ApiClient builds WebSocket URLs from the `/api` REST base.
    # Keep the direct route for reverse proxies that strip it.
    path('api/ws/chat', ChatEventsConsumer.as_asgi()),
]

application = ProtocolTypeRouter(
    {
        'http': django_asgi_app,
        'websocket': AuthMiddlewareStack(
            URLRouter(websocket_urlpatterns)
        ),
    }
)
