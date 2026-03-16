// Dark theme configuration for the pointer inspector.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InspectorTheme {
  // ─── Core palette ───
  static const _bg = Color(0xFF08090D);
  static const _surface = Color(0xFF0F1117);
  static const _surfaceLight = Color(0xFF171B26);
  static const _border = Color(0xFF272C38);
  static const _accent = Color(0xFF58A6FF);
  static const _accentDim = Color(0xFF1F6FEB);
  static const _green = Color(0xFF3FB950);
  static const _red = Color(0xFFF85149);
  static const _orange = Color(0xFFD29922);
  static const _purple = Color(0xFFBC8CFF);
  static const _text = Color(0xFFE6EDF3);
  static const _textDim = Color(0xFF8B949E);
  static const _cyan = Color(0xFF56D4DD);

  // ─── Semantic colors ───
  static const Color background = _bg;
  static const Color surface = _surface;
  static const Color surfaceLight = _surfaceLight;
  static const Color border = _border;
  static const Color accent = _accent;
  static const Color accentDim = _accentDim;
  static const Color success = _green;
  static const Color error = _red;
  static const Color warning = _orange;
  static const Color purple = _purple;
  static const Color text = _text;
  static const Color textDim = _textDim;
  static const Color padding = Color(0xFF3D444D);
  static const Color structType = _orange;
  static const Color arrayType = _cyan;
  static const Color unionType = Color(0xFFFF7B72);

  // ─── Type name colors ───
  static Color typeColor(String typeName) {
    return switch (typeName) {
      'Int8' || 'Int16' || 'Int32' || 'Int64' => _accent,
      'Uint8' || 'Uint16' || 'Uint32' || 'Uint64' => const Color(0xFF79C0FF),
      'Float' || 'Double' => _purple,
      'Bool' => _orange,
      _ when typeName.startsWith('Pointer') => _green,
      _ when typeName.startsWith('Array') => _cyan,
      '[pad]' => padding,
      _ => _textDim,
    };
  }

  // ─── Text styles (increased sizes) ───
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: _text,
        height: 1.5,
      );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        color: _textDim,
        height: 1.5,
      );

  static TextStyle get heading => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: _text,
        letterSpacing: 0.3,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: _textDim,
        letterSpacing: 0.5,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        color: _text,
        height: 1.5,
      );

  // ─── ThemeData ───
  static ThemeData get themeData => ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bg,
        canvasColor: _bg,
        colorScheme: const ColorScheme.dark(
          surface: _surface,
          primary: _accent,
          error: _red,
          onSurface: _text,
        ),
        cardTheme: CardThemeData(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _border, width: 1),
          ),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _accent, width: 2),
          ),
          hintStyle: GoogleFonts.jetBrainsMono(fontSize: 13, color: _textDim),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentDim,
            foregroundColor: _text,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );
}
