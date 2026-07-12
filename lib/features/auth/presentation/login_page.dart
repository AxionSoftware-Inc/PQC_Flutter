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
  final TextEditingController _usernameController = TextEditingController();
  String? _suggestedName;

  @override
  void initState() {
    super.initState();
    _primeSuggestion();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _primeSuggestion() async {
    final suggestedName = await widget.sessionController
        .suggestedBootstrapName();
    if (!mounted) {
      return;
    }
    setState(() {
      _suggestedName = suggestedName;
      if (_usernameController.text.trim().isEmpty) {
        _usernameController.text = suggestedName;
      }
    });
  }

  Future<void> _submit([String? username]) async {
    final value = (username ?? _usernameController.text).trim();
    if (value.isEmpty) {
      return;
    }

    await widget.sessionController.login(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final suggestedName = _suggestedName ?? 'Loading...';

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
                    'PQC Messenger Workspace',
                    style: theme.textTheme.headlineSmall,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'Manual authni yengillashtirdim: shu qurilma uchun tayyor test profili bilan tez kirishingiz mumkin. Xohlasangiz nomni o\'zgartirasiz, qolgan kalitlar avtomatik biriktiriladi.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xl),
                  AppStatusBanner(
                    message: 'Recommended test profile: $suggestedName',
                    leading: Icon(
                      Icons.memory_rounded,
                      color: colors.info,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  AppTextField(
                    controller: _usernameController,
                    labelText: 'Display name',
                    onSubmitted: _submit,
                  ),
                  SizedBox(height: spacing.md),
                  AppPrimaryButton(
                    onPressed: widget.sessionController.isLoading
                        ? null
                        : widget.sessionController.bootstrapLogin,
                    icon: widget.sessionController.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.rocket_launch_outlined),
                    label: Text(
                      widget.sessionController.isLoading
                          ? 'Preparing...'
                          : 'Continue with this device',
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  AppSecondaryButton(
                    onPressed: widget.sessionController.isLoading
                        ? null
                        : () => _submit(),
                    label: const Text('Use custom name'),
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
