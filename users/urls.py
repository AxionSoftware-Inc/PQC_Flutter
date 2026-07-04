from django.urls import path

from users.views import DeviceSyncView, LoginView, MeView, UserListView


urlpatterns = [
    path('auth/login', LoginView.as_view(), name='login'),
    path('users', UserListView.as_view(), name='users'),
    path('users/me', MeView.as_view(), name='me'),
    path('users/me/device', DeviceSyncView.as_view(), name='device-sync'),
]
