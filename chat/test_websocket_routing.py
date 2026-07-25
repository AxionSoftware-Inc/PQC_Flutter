from django.test import SimpleTestCase

from config.asgi import websocket_urlpatterns


class WebSocketRoutingTests(SimpleTestCase):
    def test_api_prefixed_chat_route_is_registered(self):
        matching_routes = [
            route
            for route in websocket_urlpatterns
            if route.pattern.match('api/ws/chat') is not None
        ]

        self.assertEqual(len(matching_routes), 1)
