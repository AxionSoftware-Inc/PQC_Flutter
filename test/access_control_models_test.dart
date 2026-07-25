import 'package:chat_core/chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace access snapshot fails closed for unknown permissions', () {
    final snapshot = WorkspaceAccessSnapshot.fromJson({
      'workspace_id': 7,
      'workspace_member_id': 12,
      'built_in_role': 'member',
      'custom_roles': ['security-auditor'],
      'permissions': ['messages.send', 'audit.view'],
    });

    expect(snapshot.workspaceId, 7);
    expect(snapshot.customRoles, contains('security-auditor'));
    expect(snapshot.allows('audit.view'), isTrue);
    expect(snapshot.allows('messages.read_plaintext'), isFalse);
  });

  test('workspace access role parses a stable permission set', () {
    final role = WorkspaceAccessRole.fromJson({
      'id': 3,
      'workspace_id': 7,
      'key': 'support-lead',
      'name': 'Support lead',
      'description': '',
      'is_active': true,
      'permissions': ['members.view', 'members.view', 'groups.manage'],
    });

    expect(role.permissions, {'members.view', 'groups.manage'});
  });
}
