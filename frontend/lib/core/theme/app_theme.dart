import 'package:flutter/material.dart';

class AppTheme {
  // Spotify-like primary green
  static const Color _spotifyGreen = Color(0xFF1DB954);
  static const Color _bgDark = Color(0xFF121212);
  static const Color _surfaceDark = Color(0xFF181818);

  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _spotifyGreen, brightness: Brightness.light),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20.0, fontWeight: FontWeight.w600),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w500),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16.0),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12.0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: _spotifyGreen,
          foregroundColor: Colors.white,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: _spotifyGreen, brightness: Brightness.dark),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      scaffoldBackgroundColor: _bgDark,
      cardColor: _surfaceDark,
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20.0, fontWeight: FontWeight.w600, color: Colors.white),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w500, color: Colors.white70),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16.0, color: Colors.white70),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12.0, color: Colors.white60),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: _spotifyGreen,
          foregroundColor: Colors.black,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF222222),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.white54),
      ),
      cardTheme: base.cardTheme.copyWith(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: _spotifyGreen,
        thumbColor: _spotifyGreen,
      ),
    );
  }
}
