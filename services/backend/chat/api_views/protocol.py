from rest_framework.response import Response
from rest_framework.views import APIView

from chat.protocols import get_protocol_capabilities


class CryptoProtocolCapabilitiesView(APIView):
    """Public, immutable writer capabilities for the deployed API."""

    authentication_classes = []
    permission_classes = []

    def get(self, request):
        return Response(get_protocol_capabilities())
