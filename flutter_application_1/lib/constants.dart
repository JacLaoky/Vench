import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

// ── API ──────────────────────────────────────────────────────────────────────
const String kBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:5001');

// ── Colours ──────────────────────────────────────────────────────────────────
// Dark:  "Obsidian" — near-black with subtle purple undertone
// Light: "Zinc"     — Tailwind Zinc scale (Linear / Vercel / Shadcn standard)
//        Completely neutral grey, no purple cast — the most praised 2024 SaaS
//        light palette. Indigo accent stays vibrant on both backgrounds.
class AppColors {
  static Brightness get _b =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  static bool get _dark => _b == Brightness.dark;

  // ── Adaptive neutrals ─────────────────────────────────────────────────────
  //  dark value              │  light value (Zinc scale)
  static Color get darkBg   => _dark ? const Color(0xFF0E0E11) : const Color(0xFFFAFAFA); // Zinc-50
  static Color get card     => _dark ? const Color(0xFF16161B) : const Color(0xFFFFFFFF); // white
  static Color get surface  => _dark ? const Color(0xFF1C1C24) : const Color(0xFFF4F4F5); // Zinc-100
  static Color get surface2 => _dark ? const Color(0xFF13131A) : const Color(0xFFE4E4E7); // Zinc-200
  static Color get border   => _dark ? const Color(0xFF2A2A38) : const Color(0xFFE4E4E7); // Zinc-200
  static Color get dim      => _dark ? const Color(0xFF6B6B80) : const Color(0xFF71717A); // Zinc-500
  static Color get dimDark  => _dark ? const Color(0xFF3A3A4A) : const Color(0xFFA1A1AA); // Zinc-400

  // ── Adaptive text ─────────────────────────────────────────────────────────
  static Color get text     => _dark ? const Color(0xFFF0F0F5) : const Color(0xFF09090B); // Zinc-950
  static Color get textSub  => _dark ? const Color(0xFFBBBBCC) : const Color(0xFF52525B); // Zinc-600

  // ── Brand colours — same in both modes ───────────────────────────────────
  static const blue   = Color(0xFF6366F1);  // indigo — primary accent
  static const green  = Color(0xFF22C55E);  // profit
  static const red    = Color(0xFFF43F5E);  // loss
  static const gold   = Color(0xFFF59E0B);  // amber — R badges
  static const purple = Color(0xFF8B5CF6);  // violet — tags
  static const orange = Color(0xFFFF7A00);  // avatar fallback
  static const yellow = Color(0xFFFBBF24);  // warm yellow
}

// ── Tag color palette ──────────────────────────────────────────────
class TagColors {
  static const _palette = [
    Color(0xFF2196F3), // blue
    Color(0xFF9C27B0), // purple
    Color(0xFFFF9800), // orange
    Color(0xFF00BCD4), // cyan
    Color(0xFFE91E63), // pink
    Color(0xFF4CAF50), // green
    Color(0xFFFF5722), // deep orange
    Color(0xFF607D8B), // blue grey
  ];

  static Color forTag(String tag) {
    return _palette[tag.hashCode.abs() % _palette.length];
  }
}

// ── Time-frame label ─────────────────────────────────────────────────────────
String timeLabelFor(String period) =>
    const {
      '1W': '1 Week',
      '1M': '1 Month',
      '3M': '3 Months',
      '1Y': '1 Year',
      'YTD': 'Year-To-Date',
      'AT': 'All Time',
    }[period] ??
    '';
