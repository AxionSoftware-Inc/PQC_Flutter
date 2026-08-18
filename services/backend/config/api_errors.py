import logging

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger(__name__)


def structured_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None:
        logger.error(
            'Unhandled API exception',
            exc_info=(type(exc), exc, exc.__traceback__),
        )
        return Response(
            {
                'detail': 'Internal server error.',
                'code': 'internal_server_error',
                'status_code': status.HTTP_500_INTERNAL_SERVER_ERROR,
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    detail = response.data.get('detail') if isinstance(response.data, dict) else None
    if isinstance(detail, list) and detail:
        detail = detail[0]
    if not isinstance(detail, str):
        detail = 'Request failed.'

    response.data = {
        'detail': detail,
        'code': getattr(exc, 'default_code', 'request_failed'),
        'status_code': response.status_code,
        'errors': response.data if isinstance(response.data, dict) else None,
    }
    return response
