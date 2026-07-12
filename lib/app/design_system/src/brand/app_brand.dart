import 'package:flutter/material.dart';

@immutable
class AppSkin {
  const AppSkin({
    required this.id,
    required this.appTitle,
    required this.wordmark,
    required this.seedColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.surfaceMutedColor,
    required this.successColor,
    required this.warningColor,
    required this.dangerColor,
    this.logoUrl = '',
    this.fontFamily,
  });

  final String id;
  final String appTitle;
  final String wordmark;
  final Color seedColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color surfaceMutedColor;
  final Color successColor;
  final Color warningColor;
  final Color dangerColor;
  final String logoUrl;
  final String? fontFamily;
}

class AppSkinRegistry {
  static const String defaultSkinId = 'default';
  static const String enterpriseASkinId = 'enterpriseA';
  static const String enterpriseBSkinId = 'enterpriseB';
  static const String enterpriseCSkinId = 'enterpriseC';

  static const Map<String, AppSkin> skins = {
    defaultSkinId: AppSkin(
      id: defaultSkinId,
      appTitle: 'PQC Chat',
      wordmark: 'PQC Chat',
      seedColor: Color(0xFF0A84FF),
      primaryColor: Color(0xFF0A84FF),
      secondaryColor: Color(0xFF7A8599),
      backgroundColor: Color(0xFFF5F5F7),
      surfaceColor: Color(0xFFFFFFFF),
      surfaceMutedColor: Color(0xFFF0F2F5),
      successColor: Color(0xFF1C8C5E),
      warningColor: Color(0xFFC97A16),
      dangerColor: Color(0xFFC34040),
    ),
    enterpriseASkinId: AppSkin(
      id: enterpriseASkinId,
      appTitle: 'Northline Secure',
      wordmark: 'Northline',
      seedColor: Color(0xFF0F766E),
      primaryColor: Color(0xFF0B5F58),
      secondaryColor: Color(0xFF466864),
      backgroundColor: Color(0xFFF5F8F8),
      surfaceColor: Color(0xFFFFFFFF),
      surfaceMutedColor: Color(0xFFE7F0EF),
      successColor: Color(0xFF1C8C5E),
      warningColor: Color(0xFFAD6A12),
      dangerColor: Color(0xFFB53E3E),
    ),
    enterpriseBSkinId: AppSkin(
      id: enterpriseBSkinId,
      appTitle: 'Summit Grid',
      wordmark: 'Summit Grid',
      seedColor: Color(0xFF7C3AED),
      primaryColor: Color(0xFF6A30CC),
      secondaryColor: Color(0xFF70618D),
      backgroundColor: Color(0xFFF7F6FC),
      surfaceColor: Color(0xFFFFFFFF),
      surfaceMutedColor: Color(0xFFEEEAF8),
      successColor: Color(0xFF198B62),
      warningColor: Color(0xFFC27718),
      dangerColor: Color(0xFFC63F55),
    ),
    enterpriseCSkinId: AppSkin(
      id: enterpriseCSkinId,
      appTitle: 'Atlas Finance',
      wordmark: 'Atlas',
      seedColor: Color(0xFF9A3412),
      primaryColor: Color(0xFF842C10),
      secondaryColor: Color(0xFF786456),
      backgroundColor: Color(0xFFFBF7F4),
      surfaceColor: Color(0xFFFFFFFF),
      surfaceMutedColor: Color(0xFFF4E9DF),
      successColor: Color(0xFF227B57),
      warningColor: Color(0xFFB26916),
      dangerColor: Color(0xFFBD3B3B),
    ),
  };

  static AppSkin resolve(String skinId) {
    return skins[skinId] ?? skins[defaultSkinId]!;
  }
}

enum BrandAccentPolicy { baseOnly, workspaceOverride }

@immutable
class ResolvedWorkspaceBrand {
  const ResolvedWorkspaceBrand({
    required this.accentColor,
    required this.logoUrl,
    required this.label,
    required this.policy,
    this.isFallback = false,
  });

  final Color accentColor;
  final String logoUrl;
  final String label;
  final BrandAccentPolicy policy;
  final bool isFallback;
}
