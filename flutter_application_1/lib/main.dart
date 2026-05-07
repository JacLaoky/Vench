import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/screens/portfolio_screen.dart';
import 'package:flutter_application_1/screens/journal_screen.dart';
import 'package:flutter_application_1/screens/performance_screen.dart';
import 'package:flutter_application_1/screens/calculator_screen.dart';

void main() {
  runApp(const MyTradingApp());
}

class MyTradingApp extends StatelessWidget {
  const MyTradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trading Journal',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const MainNavigation(),
    );
  }
}

// ── Theme builder ─────────────────────────────────────────────────────────────
ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg      = isDark ? const Color(0xFF0E0E11) : const Color(0xFFFAFAFA); // Zinc-50
  final cardBg  = isDark ? const Color(0xFF16161B) : const Color(0xFFFFFFFF);
  final text    = isDark ? const Color(0xFFF0F0F5) : const Color(0xFF09090B); // Zinc-950
  final dimText = isDark ? const Color(0xFF6B6B80) : const Color(0xFF71717A); // Zinc-500

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: bg,
    cardColor: cardBg,
    textTheme: GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(bodyColor: text, displayColor: text),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: text),
      titleTextStyle: GoogleFonts.inter(
        color: text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    ),
    dividerColor: isDark ? const Color(0xFF2A2A38) : const Color(0xFFDFDFEC),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: brightness,
      surface: cardBg,
      onSurface: text,
      onSurfaceVariant: dimText,
    ),
  );
}

// ================= Bottom Navigation =================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  static const _screens = [
    PortfolioScreen(),
    JournalScreen(),
    PerformanceScreen(),
    CalculatorScreen(),
  ];

  static const _navItems = [
    _NavItem(Icons.bar_chart_rounded,       Icons.bar_chart_rounded,       'Portfolio'),
    _NavItem(Icons.menu_book_outlined,      Icons.menu_book_rounded,       'Journal'),
    _NavItem(Icons.insights_outlined,       Icons.insights_rounded,        'Performance'),
    _NavItem(Icons.calculate_outlined,      Icons.calculate_rounded,       'Calculator'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,   // content goes behind the floating nav
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (i) { if (i != _currentIndex) setState(() => _currentIndex = i); },
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

// ── Floating pill nav bar ─────────────────────────────────────────────────────
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.blue.withValues(alpha: 0.08),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (i) {
              final item      = items[i];
              final isActive  = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.blue.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          size: 22,
                          color: isActive
                              ? AppColors.blue
                              : AppColors.dim,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isActive
                                ? AppColors.blue
                                : AppColors.dim,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
