import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../brand/app_brand.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceStrong,
    required this.border,
    required this.textMuted,
    required this.primary,
    required this.primarySoft,
    required this.secondary,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.chatMine,
    required this.chatPeer,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceStrong;
  final Color border;
  final Color textMuted;
  final Color primary;
  final Color primarySoft;
  final Color secondary;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color chatMine;
  final Color chatPeer;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceStrong,
    Color? border,
    Color? textMuted,
    Color? primary,
    Color? primarySoft,
    Color? secondary,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? chatMine,
    Color? chatPeer,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      border: border ?? this.border,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      chatMine: chatMine ?? this.chatMine,
      chatPeer: chatPeer ?? this.chatPeer,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceStrong: Color.lerp(surfaceStrong, other.surfaceStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      chatMine: Color.lerp(chatMine, other.chatMine, t)!,
      chatPeer: Color.lerp(chatPeer, other.chatPeer, t)!,
    );
  }
}

@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) {
      return this;
    }
    return AppSpacing(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      xxl: lerpDouble(xxl, other.xxl, t)!,
    );
  }
}

@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
  });

  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double pill;

  @override
  AppRadii copyWith({
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? pill,
  }) {
    return AppRadii(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) {
      return this;
    }
    return AppRadii(
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}

@immutable
class AppShadows extends ThemeExtension<AppShadows> {
  const AppShadows({
    required this.card,
    required this.floating,
  });

  final List<BoxShadow> card;
  final List<BoxShadow> floating;

  @override
  AppShadows copyWith({
    List<BoxShadow>? card,
    List<BoxShadow>? floating,
  }) {
    return AppShadows(
      card: card ?? this.card,
      floating: floating ?? this.floating,
    );
  }

  @override
  AppShadows lerp(ThemeExtension<AppShadows>? other, double t) {
    if (other is! AppShadows) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

@immutable
class AppDurations extends ThemeExtension<AppDurations> {
  const AppDurations({
    required this.fast,
    required this.normal,
  });

  final Duration fast;
  final Duration normal;

  @override
  AppDurations copyWith({
    Duration? fast,
    Duration? normal,
  }) {
    return AppDurations(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
    );
  }

  @override
  AppDurations lerp(ThemeExtension<AppDurations>? other, double t) {
    if (other is! AppDurations) {
      return this;
    }
    return AppDurations(
      fast: t < 0.5 ? fast : other.fast,
      normal: t < 0.5 ? normal : other.normal,
    );
  }
}

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
    final scheme = ColorScheme.fromSeed(
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
        ? _mix(skin.backgroundColor, Colors.black, 0.88)
        : skin.backgroundColor;
    final surface = isDark
        ? _mix(skin.surfaceColor, Colors.black, 0.78)
        : skin.surfaceColor;
    final surfaceMuted = isDark
        ? _mix(skin.surfaceMutedColor, Colors.black, 0.72)
        : skin.surfaceMutedColor;
    final border = isDark ? const Color(0xFF303440) : const Color(0xFFE3E6EC);
    final foreground = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF111827);
    final colors = AppColors(
      background: background,
      surface: surface,
      surfaceMuted: surfaceMuted,
      surfaceStrong: isDark
          ? _mix(surfaceMuted, Colors.white, 0.08)
          : _mix(skin.surfaceMutedColor, Colors.white, 0.35),
      border: border,
      textMuted: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6E7381),
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
      chatPeer: isDark ? const Color(0xFF232834) : const Color(0xFFE9EAEE),
    );
    const spacing = AppSpacing(
      xs: 4,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      xxl: 32,
    );
    const radii = AppRadii(
      sm: 10,
      md: 16,
      lg: 22,
      xl: 28,
      pill: 999,
    );
    final shadows = AppShadows(
      card: [
        BoxShadow(
          color: const Color(0x14000000),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
      floating: [
        BoxShadow(
          color: const Color(0x16000000),
          blurRadius: 24,
          offset: const Offset(0, 10),
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
    final textTheme = baseTextTheme.copyWith(
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
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        color: colors.textMuted,
        fontWeight: FontWeight.w500,
      ),
    ).apply(
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
          borderSide: BorderSide(color: colors.border),
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
        backgroundColor: colors.surface.withValues(alpha: 0.94),
        indicatorColor: _mix(accent, Colors.white, 0.78),
        surfaceTintColor: Colors.transparent,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent);
          }
          return IconThemeData(color: colors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final style = textTheme.labelMedium ?? const TextStyle();
          if (states.contains(WidgetState.selected)) {
            return style.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            );
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
      extensions: [
        colors,
        spacing,
        radii,
        shadows,
        durations,
      ],
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
