from django.apps import AppConfig


class UsersConfig(AppConfig):
    name = 'users'

    def ready(self) -> None:
        from . import signals  # noqa: F401
