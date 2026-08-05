from django.urls import path

from .views import InvitationCreateView, MemberAssignmentView, MemberDeactivateView, MemberListView, RbacMeView, RoleDetailView, RoleListCreateView

urlpatterns = [
    path('me', RbacMeView.as_view()),
    path('roles', RoleListCreateView.as_view()),
    path('roles/<int:role_id>', RoleDetailView.as_view()),
    path('members', MemberListView.as_view()),
    path('members/<int:member_id>/role', MemberAssignmentView.as_view()),
    path('members/<int:member_id>/deactivate', MemberDeactivateView.as_view()),
    path('invitations', InvitationCreateView.as_view()),
]
