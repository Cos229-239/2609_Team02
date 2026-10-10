import 'package:flutter/material.dart';

/// Famotive brand colors, taken from the lo-fidelity wireframes: a
/// confident blue for primary actions/navigation and a supportive green
/// for growth/reward moments (XP, success states, "Assign Rewards").
class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF2455C9);
  static const Color growthGreen = Color(0xFF43A047);
  static const Color surfaceLight = Color(0xFFF7F9FC);
  static const Color textDark = Color(0xFF1A1E27);

  // Dark mode counterparts. The blue is lifted a little so it still reads
  // as "Famotive blue" (and keeps white button text legible) on the dark
  // navy background; the green is lifted for the same reason.
  static const Color primaryBlueDark = Color(0xFF4C7EF3);
  static const Color growthGreenDark = Color(0xFF5CB860);
  static const Color surfaceDark = Color(0xFF0F131A);
  static const Color surfaceDarkRaised = Color(0xFF181D27);
  static const Color inputFillDark = Color(0xFF1E2431);
  static const Color textLight = Color(0xFFE8EBF2);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;
    final raised = isDark ? AppColors.surfaceDarkRaised : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    // Light mode keeps the original seed-derived scheme exactly; dark mode
    // pins the brand blue/green and the dark surfaces on top of it.
    final colorScheme = isDark
        ? ColorScheme.fromSeed(
            seedColor: AppColors.primaryBlue,
            brightness: Brightness.dark,
          ).copyWith(
            primary: AppColors.primaryBlueDark,
            onPrimary: Colors.white,
            secondary: AppColors.growthGreenDark,
            onSecondary: Colors.white,
            surface: AppColors.surfaceDarkRaised,
            onSurface: AppColors.textLight,
          )
        : ColorScheme.fromSeed(
            seedColor: AppColors.primaryBlue,
            secondary: AppColors.growthGreen,
            brightness: Brightness.light,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      dividerColor: isDark ? Colors.grey.shade800 : null,
      appBarTheme: AppBarTheme(
        backgroundColor: raised,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.inputFillDark : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.surfaceDarkRaised : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: raised,
        indicatorColor: colorScheme.primary.withValues(alpha: isDark ? 0.28 : 0.12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26314A) : AppColors.textDark.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: textColor),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: textColor),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        bodyMedium: TextStyle(color: textColor),
      ),
    );
  }
}

/// Small helpers for the few places that used to hard-code `Colors.white`
/// card backgrounds / `Colors.black` text, so they follow light/dark mode.
extension FamotiveThemeColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Background for raised rows/cards (white in light mode).
  Color get raisedSurface => isDarkMode ? AppColors.surfaceDarkRaised : Colors.white;

  /// Hairline border for raised rows (grey.shade200 in light mode).
  Color get subtleBorder => isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200;

  /// Primary text color (near-black in light mode).
  Color get strongText => isDarkMode ? AppColors.textLight : AppColors.textDark;

  /// Muted track/background for pills and toggles (grey.shade200 in light mode).
  Color get mutedFill => isDarkMode ? const Color(0xFF242B38) : Colors.grey.shade200;
}
