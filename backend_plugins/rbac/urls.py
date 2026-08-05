from django.urls import path

from .views import MemberAssignmentView, MemberListView, RbacMeView, RoleDetailView, RoleListCreateView

urlpatterns = [
    path('me', RbacMeView.as_view()),
    path('roles', RoleListCreateView.as_view()),
    path('roles/<int:role_id>', RoleDetailView.as_view()),
    path('members', MemberListView.as_view()),
    path('members/<int:member_id>/role', MemberAssignmentView.as_view()),
]
