from django.urls import path

from .views import DefaultRoleBootstrapView, InvitationCreateView, MemberAssignmentView, MemberDeactivateView, MemberListView, MemberReactivateView, RbacMeView, RoleDetailView, RoleListCreateView

urlpatterns = [
    path('me', RbacMeView.as_view()),
    path('roles', RoleListCreateView.as_view()),
    path('roles/<int:role_id>', RoleDetailView.as_view()),
    path('roles/bootstrap-defaults', DefaultRoleBootstrapView.as_view()),
    path('members', MemberListView.as_view()),
    path('members/<int:member_id>/role', MemberAssignmentView.as_view()),
    path('members/<int:member_id>/deactivate', MemberDeactivateView.as_view()),
    path('members/<int:member_id>/reactivate', MemberReactivateView.as_view()),
    path('invitations', InvitationCreateView.as_view()),
]
