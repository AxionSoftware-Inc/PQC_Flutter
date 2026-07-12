import 'package:flutter/material.dart';

import '../../../../core/models/organization_context.dart';
import '../../../../core/models/session_user.dart';
import 'app_brand.dart';

class WorkspaceBrandResolver {
  const WorkspaceBrandResolver._();

  static ResolvedWorkspaceBrand? fromSession(SessionUser? sessionUser) {
    if (sessionUser == null) {
      return null;
    }
    final organization = _findActiveOrganization(sessionUser);
    if (organization == null) {
      return null;
    }
    final color = _parseBrandColor(organization.brandColor);
    final hasAccent = color != null;
    final hasLogo = organization.brandLogoUrl.trim().isNotEmpty;
    if (!hasAccent && !hasLogo) {
      return null;
    }
    return ResolvedWorkspaceBrand(
      accentColor: color ?? const Color(0xFF1749D1),
      logoUrl: organization.brandLogoUrl.trim(),
      label: organization.name,
      policy: hasAccent
          ? BrandAccentPolicy.workspaceOverride
          : BrandAccentPolicy.baseOnly,
      isFallback: !hasAccent,
    );
  }

  static OrganizationSummary? _findActiveOrganization(SessionUser sessionUser) {
    for (final organization in sessionUser.organizations) {
      for (final workspace in organization.workspaces) {
        if (workspace.id == sessionUser.activeWorkspaceId) {
          return organization;
        }
      }
    }
    return sessionUser.organizations.isEmpty ? null : sessionUser.organizations.first;
  }

  static Color? _parseBrandColor(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    var normalized = value.replaceFirst('#', '');
    if (normalized.length == 6) {
      normalized = 'FF$normalized';
    }
    if (normalized.length != 8) {
      return null;
    }
    final colorValue = int.tryParse(normalized, radix: 16);
    if (colorValue == null) {
      return null;
    }
    return Color(colorValue);
  }
}
