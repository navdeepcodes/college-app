import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'spacing.dart';

class AppTheme {
  static TextTheme _textTheme(TextTheme base) {
    // Sora carries headings/titles/buttons — a geometric-humanist face
    // with real character at display sizes. Inter carries body/labels —
    // built for legibility at small UI sizes. Two faces, two clear jobs.
    final display = GoogleFonts.soraTextTheme(base);
    final body = GoogleFonts.interTextTheme(base);

    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: display.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: display.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: display.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: body.bodyLarge?.copyWith(color: AppColors.textPrimary, height: 1.4),
      bodyMedium: body.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.4),
      bodySmall: body.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.3),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.accent,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,

      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.accentBright,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        onError: Colors.white,
        outline: AppColors.border,
      ),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textMuted,
          side: const BorderSide(color: AppColors.borderStrong),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(44, 44),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15),
        floatingLabelStyle: GoogleFonts.inter(color: AppColors.accentBright, fontSize: 13),
        errorStyle: GoogleFonts.inter(color: AppColors.danger, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceRaised),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.75,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBackgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        actionTextColor: AppColors.accentBright,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSunken,
        selectedColor: AppColors.accent.withValues(alpha: 0.22),
        disabledColor: AppColors.surfaceSunken,
        labelStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        secondaryLabelStyle: GoogleFonts.inter(color: AppColors.accentBright, fontSize: 13),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentBright,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14.5),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.accent,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
