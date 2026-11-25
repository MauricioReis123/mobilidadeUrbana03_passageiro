import 'package:flutter/material.dart';
import '../constants/omni_constants.dart';

/// Tema Oficial OMNI — Neon Luxuoso (Fidelidade 1:1 ao Preview TSX)
class OmniTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: OmniConstants.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: OmniConstants.neonCyan,
        onPrimary: Colors.black,
        secondary: OmniConstants.neonCyanDark,
        onSecondary: Colors.white,
        surface: OmniConstants.darkSurface,
        onSurface: OmniConstants.textPrimary,
        error: OmniConstants.rubyRedAlert,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: OmniConstants.darkSurface,
        foregroundColor: OmniConstants.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: OmniConstants.neonCyan,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
          shadowColor: OmniConstants.neonCyan.withValues(alpha: 0.45),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        hintStyle: const TextStyle(color: OmniConstants.textDim, fontSize: 13),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: OmniConstants.darkCard,
        contentTextStyle: const TextStyle(color: OmniConstants.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: OmniConstants.darkBorder),
        ),
      ),
    );
  }

  /// Caixa com Efeito Luminoso Neon
  static BoxDecoration neonBoxDecoration({
    Color borderColor = OmniConstants.neonCyan,
    Color backgroundColor = OmniConstants.darkCard,
    double borderRadius = 20,
    double glowRadius = 15,
    double borderWidth = 1.2,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor.withValues(alpha: 0.45), width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: borderColor.withValues(alpha: 0.18),
          blurRadius: glowRadius,
          spreadRadius: 1,
        ),
      ],
    );
  }

  /// Caixa Estrutural Padrão (Painel Executivo)
  static BoxDecoration cardDecoration({
    Color backgroundColor = OmniConstants.darkCard,
    Color borderColor = OmniConstants.darkBorder,
    double borderRadius = 24,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}
