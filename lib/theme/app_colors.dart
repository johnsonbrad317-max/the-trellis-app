import 'package:flutter/material.dart';

/// Design tokens for the "Parchment & Botanic" system.
class AppColors {
  AppColors._();

  static const Color forestGreen = Color(0xFF1E3A2B);
  static const Color antiqueBrass = Color(0xFFB8860B);

  /// The app's antique parchment — the one background every screen paints, the
  /// same #F9F6F0 the website uses — and the light tone for text and marks on
  /// green, brass or terracotta.
  static const Color parchmentLight = Color(0xFFF9F6F0);
  static const Color vellum = Color(0xFFF8F1E0);
  /// [parchmentLight] at zero opacity — the far end of a fade INTO parchment.
  /// (Fading to plain transparent would pass through grey on the way.)
  static const Color parchmentClear = Color(0x00F9F6F0);
  static const Color vellumBorder = Color(0x261E3A2B);

  /// Muted terracotta / burnt sienna — stands in for stock red everywhere an
  /// alert, error, or "needs attention" signal is called for.
  static const Color terracotta = Color(0xFF9E4B2F);
  static const Color terracottaTint = Color(0xFFF1E1D6);
}
