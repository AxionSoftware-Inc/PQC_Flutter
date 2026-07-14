import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../session_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.sessionController});

  final SessionController sessionController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final spacing = context.appSpacing;

    return AppScaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: EdgeInsets.all(spacing.xl),
            child: AppSurfaceCard(
              padding: EdgeInsets.all(spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppBrandMark(),
                  SizedBox(height: spacing.xl),
                  Text(
                    'Sign in to PQC Chat',
                    style: theme.textTheme.headlineSmall,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'Google account bilan kiring. Shu account boshqa qurilmalarda ham ishlaydi; device nomi alohida account yaratmaydi.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xl),
                  SizedBox(height: spacing.xl),
                  AppSecondaryButton(
                    onPressed: widget.sessionController.isLoading
                        ? null
                        : () => widget.sessionController.loginWithGoogle(),
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Continue with Google'),
                  ),
                  if (widget.sessionController.error != null) ...[
                    SizedBox(height: spacing.md),
                    AppStatusBanner(
                      message: widget.sessionController.error!,
                      tone: AppStatusTone.danger,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
