import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/app/design_system/app_design_system.dart';
import 'package:pqc_chat_app/core/models/organization_context.dart';
import 'package:pqc_chat_app/core/models/session_user.dart';

void main() {
  test('theme factory builds valid theme data for multiple skins', () {
    final defaultTheme = AppThemeFactory.build(
      skin: AppSkinRegistry.resolve(AppSkinRegistry.defaultSkinId),
    );
    final enterpriseTheme = AppThemeFactory.build(
      skin: AppSkinRegistry.resolve(AppSkinRegistry.enterpriseASkinId),
    );

    expect(defaultTheme.extension<AppColors>(), isNotNull);
    expect(defaultTheme.extension<AppSpacing>(), isNotNull);
    expect(enterpriseTheme.extension<AppRadii>(), isNotNull);
    expect(defaultTheme.colorScheme.primary, isNot(equals(enterpriseTheme.colorScheme.primary)));
  });

  test('workspace brand resolver applies organization accent when available', () {
    const session = SessionUser(
      id: 7,
      accountId: 9,
      username: 'riley',
      displayName: 'Riley',
      deviceId: 'device-a',
      token: 'token',
      activeWorkspaceId: 12,
      organizations: [
        OrganizationSummary(
          id: 3,
          name: 'Atlas',
          slug: 'atlas',
          brandColor: '#0F766E',
          brandLogoUrl: 'https://example.com/logo.png',
          workspaces: [
            WorkspaceSummary(
              id: 12,
              organizationId: 3,
              name: 'Ops',
              slug: 'ops',
            ),
          ],
        ),
      ],
    );

    final brand = WorkspaceBrandResolver.fromSession(session);

    expect(brand, isNotNull);
    expect(brand!.accentColor, const Color(0xFF0F766E));
    expect(brand.logoUrl, 'https://example.com/logo.png');
    expect(brand.policy, BrandAccentPolicy.workspaceOverride);
  });

  testWidgets('login page renders under multiple skins', (tester) async {
    Future<void> pumpWithSkin(String skinId) async {
      final skin = AppSkinRegistry.resolve(skinId);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeFactory.build(skin: skin),
          home: AppBrandScope(
            skin: skin,
            brand: null,
            child: Scaffold(
              body: Column(
                children: const [
                  AppBrandMark(),
                  AppEmptyState(message: 'Empty'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpWithSkin(AppSkinRegistry.defaultSkinId);
    expect(find.text('PQC Chat'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);

    await pumpWithSkin(AppSkinRegistry.enterpriseASkinId);
    expect(find.text('Northline'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
  });
}
