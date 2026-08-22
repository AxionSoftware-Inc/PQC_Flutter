import 'package:flutter/material.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../session_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.sessionController});

  final SessionController sessionController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final spacing = context.appSpacing;

    final curved = CurvedAnimation(
      parent: _motionController,
      curve: Curves.easeOutCubic,
    );
    return AppScaffold(
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _AmbientOrb(
              color: colors.primary.withValues(alpha: 0.20),
              size: 320,
            ),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _AmbientOrb(
              color: colors.secondary.withValues(alpha: 0.12),
              size: 380,
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: AnimatedBuilder(
                  animation: curved,
                  builder: (context, child) => Opacity(
                    opacity: curved.value,
                    child: Transform.translate(
                      offset: Offset(0, 28 * (1 - curved.value)),
                      child: child,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(context.appRadii.xl),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.surface.withValues(alpha: 0.98),
                          colors.surfaceStrong.withValues(alpha: 0.94),
                        ],
                      ),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.10),
                          blurRadius: 48,
                          spreadRadius: -12,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(spacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AppBrandMark(),
                          SizedBox(height: spacing.xxl),
                          Text(
                            context.antiQText(
                              uz: 'antiQ akkauntiga kirish',
                              en: 'Sign in to antiQ',
                            ),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.1,
                            ),
                          ),
                          SizedBox(height: spacing.sm),
                          Text(
                            context.antiQText(
                              uz: 'Google akkauntingiz bilan kiring. Shu akkaunt boshqa qurilmalarda ham xavfsiz ishlaydi.',
                              en: 'Sign in with your Google account. The same account works securely across your devices.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          SizedBox(height: spacing.xl),
                          AppPrimaryButton(
                            onPressed: widget.sessionController.isLoading
                                ? null
                                : () => widget.sessionController
                                      .loginWithGoogle(),
                            icon: widget.sessionController.isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                widget.sessionController.isLoading
                                    ? context.antiQText(
                                        uz: 'Ulanmoqda…',
                                        en: 'Connecting…',
                                      )
                                    : context.antiQText(
                                        uz: 'Google orqali davom etish',
                                        en: 'Continue with Google',
                                      ),
                                key: ValueKey(
                                  widget.sessionController.isLoading,
                                ),
                              ),
                            ),
                          ),
                          if (widget.sessionController.error != null) ...[
                            SizedBox(height: spacing.md),
                            AppStatusBanner(
                              message: widget.sessionController.error!,
                              tone: AppStatusTone.danger,
                              compact: true,
                            ),
                          ],
                          SizedBox(height: spacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: colors.textMuted,
                              ),
                              SizedBox(width: spacing.xs),
                              Text(
                                context.antiQText(
                                  uz: 'Shifrlangan va korporativ darajada himoyalangan',
                                  en: 'Encrypted and protected for your workspace',
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.textMuted,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
