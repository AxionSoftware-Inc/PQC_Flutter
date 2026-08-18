import 'package:flutter/material.dart';

import '../brand/app_brand.dart';
import 'app_theme_extensions.dart';

export 'app_theme_extensions.dart';

class AppThemeFactory {
  const AppThemeFactory._();

  static ThemeData build({
    required AppSkin skin,
    ResolvedWorkspaceBrand? brand,
    Brightness brightness = Brightness.light,
  }) {
    final accent = brand?.policy == BrandAccentPolicy.workspaceOverride
        ? brand!.accentColor
        : skin.primaryColor;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          secondary: skin.secondaryColor,
          surface: brightness == Brightness.dark
              ? _mix(skin.surfaceColor, Colors.black, 0.82)
              : skin.surfaceColor,
        );
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF05070A)
        : _mix(skin.backgroundColor, const Color(0xFFF7F8FB), 0.72);
    final surface = isDark ? const Color(0xFF0C0F14) : Colors.white;
    final surfaceMuted = isDark
        ? const Color(0xFF13171E)
        : const Color(0xFFF2F4F7);
    final border = isDark ? const Color(0xFF222832) : const Color(0xFFE7EAF0);
    final foreground = isDark
        ? const Color(0xFFF3F4F6)
        : const Color(0xFF111827);
    final colors = AppColors(
      background: background,
      surface: surface,
      surfaceMuted: surfaceMuted,
      surfaceStrong: isDark
          ? _mix(surfaceMuted, Colors.white, 0.08)
          : _mix(skin.surfaceMutedColor, Colors.white, 0.35),
      border: border,
      textMuted: isDark ? const Color(0xFF929AA8) : const Color(0xFF707785),
      primary: accent,
      primarySoft: isDark
          ? _mix(accent, Colors.black, 0.72)
          : _softTone(accent),
      secondary: skin.secondaryColor,
      success: skin.successColor,
      successSoft: isDark
          ? _mix(skin.successColor, Colors.black, 0.7)
          : _softTone(skin.successColor),
      warning: skin.warningColor,
      warningSoft: isDark
          ? _mix(skin.warningColor, Colors.black, 0.7)
          : _softTone(skin.warningColor),
      danger: skin.dangerColor,
      dangerSoft: isDark
          ? _mix(skin.dangerColor, Colors.black, 0.7)
          : _softTone(skin.dangerColor),
      info: accent,
      infoSoft: isDark ? _mix(accent, Colors.black, 0.7) : _softTone(accent),
      chatMine: accent,
      chatPeer: isDark ? const Color(0xFF151A22) : const Color(0xFFF0F2F5),
    );
    const spacing = AppSpacing(xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32);
    const radii = AppRadii(sm: 10, md: 15, lg: 20, xl: 26, pill: 999);
    final shadows = AppShadows(
      card: [
        BoxShadow(
          color: Color(isDark ? 0x38000000 : 0x0D111827),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
      floating: [
        BoxShadow(
          color: Color(isDark ? 0x52000000 : 0x16111827),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    );
    const durations = AppDurations(
      fast: Duration(milliseconds: 160),
      normal: Duration(milliseconds: 240),
    );
    final baseTextTheme = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = baseTextTheme
        .copyWith(
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.45),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.45),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          labelMedium: baseTextTheme.labelMedium?.copyWith(
            color: colors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(
          bodyColor: foreground,
          displayColor: foreground,
          fontFamily: skin.fontFamily,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: colors.border.withValues(alpha: 0.72),
        thickness: 0.7,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.lg),
          side: BorderSide(color: colors.border),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceMuted,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.lg,
          vertical: spacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colors.border.withValues(alpha: 0.72)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.xl,
            vertical: spacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: colors.border),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.xl,
            vertical: spacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: textTheme.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface.withValues(alpha: isDark ? 0.98 : 0.94),
        indicatorColor: isDark
            ? _mix(accent, Colors.black, 0.42)
            : _mix(accent, Colors.white, 0.78),
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent);
          }
          return IconThemeData(color: colors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final style = textTheme.labelMedium ?? const TextStyle();
          if (states.contains(WidgetState.selected)) {
            return style.copyWith(color: accent, fontWeight: FontWeight.w700);
          }
          return style;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.pill),
          side: BorderSide(color: colors.border),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs,
        ),
        labelStyle: textTheme.bodySmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.xl),
          side: BorderSide(color: colors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF1B2029)
            : const Color(0xFF171A21),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.md),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.10)),
        ),
      ),
      extensions: [colors, spacing, radii, shadows, durations],
    );
  }

  static Color _softTone(Color color) => _mix(color, Colors.white, 0.86);

  static Color _mix(Color a, Color b, double ratioToB) {
    return Color.lerp(a, b, ratioToB)!;
  }
}
extension AppThemeBuildContext on BuildContext {
  ThemeData get theme => Theme.of(this);

  AppColors get appColors => theme.extension<AppColors>()!;

  AppSpacing get appSpacing => theme.extension<AppSpacing>()!;

  AppRadii get appRadii => theme.extension<AppRadii>()!;

  AppShadows get appShadows => theme.extension<AppShadows>()!;

  AppDurations get appDurations => theme.extension<AppDurations>()!;
}
