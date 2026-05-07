import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/utils.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';
import 'package:flutter_application_1/screens/detail/daily_detail_screen.dart';
import 'package:flutter_application_1/screens/detail/monthly_detail_screen.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';
import 'package:flutter_application_1/widgets/tag_chip.dart';
import 'package:flutter_application_1/screens/tag_stats_screen.dart';

// ================= 页面二：My Journal =================
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  int _selectedTab = 0;
  bool isLoading = true;
  bool hasError = false;

  List<dynamic> dailyData = [];
  List<dynamic> monthlyData = [];

  int? touchedMonthlyIndex;
  String? touchedDate;
  String? touchedProfitValue;
  double? touchedProfitRaw;

  final Map<String, String> _dailyNotes = {};

  // Search query for Daily tab
  String _searchQuery = '';

  // Tag filter state
  String? _activeTag;
  List<String> _allTags = [];

  bool _wasDraggingOnChart = false;
  int _chartDragEventCount = 0;

  @override
  void initState() {
    super.initState();
    fetchJournalData();
  }

  Future<void> fetchJournalData() async {
    setState(() { isLoading = true; hasError = false; });
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$kBaseUrl/api/journal')),
        http.get(Uri.parse('$kBaseUrl/api/daily_notes')),
      ]);
      final journalRes = results[0];
      final notesRes = results[1];
      if (journalRes.statusCode == 200) {
        final data = json.decode(journalRes.body);
        if (data['status'] == 'success' || data['status'] == 'empty') {
          final notes = <String, String>{};
          if (notesRes.statusCode == 200) {
            final nd = json.decode(notesRes.body) as Map<String, dynamic>;
            nd.forEach((k, v) => notes[k] = v as String);
          }
          final newDailyData = List<dynamic>.from(data['daily'] ?? []);
          final newMonthlyData = List<dynamic>.from(data['monthly'] ?? []);
          // Extract all unique tags from nested trades
          final tagSet = <String>{};
          for (final day in newDailyData) {
            final tickers = day['tickers'] as List? ?? [];
            for (final ticker in tickers) {
              final trades = ticker['trades'] as List? ?? [];
              for (final trade in trades) {
                final rawTags = trade['tags'];
                if (rawTags is List) {
                  for (final t in rawTags) {
                    if (t is String && t.isNotEmpty) tagSet.add(t);
                  }
                }
              }
            }
          }
          setState(() {
            dailyData = newDailyData;
            monthlyData = newMonthlyData;
            _dailyNotes.addAll(notes);
            _allTags = tagSet.toList()..sort();
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('获取复盘数据失败: $e');
      setState(() { isLoading = false; hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Journal',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.local_offer_rounded, color: AppColors.blue),
            tooltip: 'Tag Analytics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TagStatsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildJournalTab('Daily', 0),
                const SizedBox(width: 8),
                _buildJournalTab('Monthly', 1),
                const SizedBox(width: 8),
                _buildJournalTab('Calendar', 2),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search bar — only visible in Daily tab
          if (_selectedTab == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                onChanged: (q) =>
                    setState(() => _searchQuery = q.trim().toLowerCase()),
                style: TextStyle(color: AppColors.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search ticker...',
                  hintStyle: const TextStyle(color: Color(0xFF444444)),
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.dim, size: 20),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

          // Tag filter bar — only visible in Daily tab when tags exist
          if (_selectedTab == 0 && _allTags.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // "All" chip
                  GestureDetector(
                    onTap: () => setState(() => _activeTag = null),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _activeTag == null
                            ? AppColors.blue.withValues(alpha: 0.25)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _activeTag == null
                              ? AppColors.blue.withValues(alpha: 0.7)
                              : AppColors.border,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'All',
                        style: TextStyle(
                          color: _activeTag == null ? AppColors.blue : AppColors.dim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // One chip per tag
                  ..._allTags.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TagChip(
                      tag: tag,
                      selected: _activeTag == tag,
                      onTap: () => setState(() => _activeTag = tag),
                    ),
                  )),
                ],
              ),
            ),
          if (_selectedTab == 0 && _allTags.isNotEmpty)
            const SizedBox(height: 12),

          Expanded(
            child: isLoading
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: 6,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: ShimmerCard(rows: 4),
                    ),
                  )
                : hasError
                    ? ErrorRetryWidget(
                        message: 'Could not load journal data.\nMake sure your backend is running.',
                        onRetry: fetchJournalData,
                      )
                    : RefreshIndicator(
                        color: AppColors.blue,
                        backgroundColor: AppColors.card,
                        onRefresh: () => fetchJournalData(),
                        child: _selectedTab == 0
                            ? _buildDynamicDailyList()
                            : _selectedTab == 1
                                ? _buildDynamicMonthlyList()
                                : _buildDynamicCalendarList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicDailyList() {
    // Apply ticker search filter
    var displayData = _searchQuery.isEmpty
        ? dailyData
        : dailyData.where((dayInfo) {
            final tickers = (dayInfo['tickers'] as List)
                .map((t) => (t['name'] as String).toLowerCase());
            return tickers.any((t) => t.contains(_searchQuery));
          }).toList();

    // Apply tag filter: only show days that have at least one trade with the active tag
    if (_activeTag != null) {
      final activeTag = _activeTag!;
      displayData = displayData.where((dayInfo) {
        final tickers = dayInfo['tickers'] as List? ?? [];
        for (final ticker in tickers) {
          final trades = ticker['trades'] as List? ?? [];
          for (final trade in trades) {
            final rawTags = trade['tags'];
            if (rawTags is List && rawTags.contains(activeTag)) return true;
          }
        }
        return false;
      }).toList();
    }

    if (displayData.isEmpty && _searchQuery.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.menu_book_outlined,
        title: 'No journal entries',
        subtitle:
            'Your daily trading records will appear here after syncing.',
      );
    }
    if (displayData.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'No trades found for "$_searchQuery".',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: displayData.length,
      itemBuilder: (context, index) {
        final dayInfo = displayData[index];
        List<Map<String, dynamic>> tickers =
            List<Map<String, dynamic>>.from(dayInfo['tickers']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: _buildDailyItem(
            dayData: dayInfo,
            day: dayInfo['day'],
            weekday: dayInfo['weekday'],
            pnl: dayInfo['pnl'],
            isProfit: dayInfo['isProfit'],
            winPct: dayInfo['winPct'],
            trades: dayInfo['trades'],
            wins: dayInfo['wins'],
            losses: dayInfo['losses'],
            comm: dayInfo['comm'],
            tickers: tickers,
          ),
        );
      },
    );
  }

  Widget _buildDynamicMonthlyList() {
    if (monthlyData.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.calendar_month_outlined,
        title: 'No monthly records',
        subtitle: 'Monthly summaries appear after syncing trades.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: monthlyData.length,
      itemBuilder: (context, index) {
        final monthInfo = monthlyData[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 40.0),
          child: _buildMonthlyItem(
            monthInfo['monthYear'],
            monthInfo['profit'],
            monthInfo['wins'],
            monthInfo['avgGain'],
            monthInfo['chart_data'] ?? [],
            monthInfo['isProfit'] ?? true,
            index,
          ),
        );
      },
    );
  }

  Widget _buildJournalTab(String text, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedTab = index;
        _searchQuery = '';
        _activeTag = null;
        touchedMonthlyIndex = null;
        touchedDate = null;
        touchedProfitValue = null;
        touchedProfitRaw = null;
        _wasDraggingOnChart = false;
        _chartDragEventCount = 0;
      }),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2C2C3E)
              : AppColors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.dim,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ================= 📅 Daily 视图 =================

  Widget _buildDailyItem({
    required Map<String, dynamic> dayData,
    required String day,
    required String weekday,
    required String pnl,
    required bool isProfit,
    required String winPct,
    required String trades,
    required String wins,
    required String losses,
    required String comm,
    required List<Map<String, dynamic>> tickers,
  }) {
    final String date = dayData['date'] as String;
    final String? savedNote = _dailyNotes[date];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(day,
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                      height: 1.0)),
              const SizedBox(height: 4),
              Text(weekday,
                  style: TextStyle(fontSize: 14, color: AppColors.text)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: _buildDailyStatColumn(
                              'PnL',
                              isProfit
                                  ? '\$${NumberFormatter.format(pnl)}'
                                  : '-\$${NumberFormatter.format(pnl)}',
                              isProfit ? AppColors.green : AppColors.red)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildDailyStatColumn(
                              'Wins', wins, AppColors.text)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _buildDailyStatColumn(
                              'Win %', winPct, AppColors.text)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildDailyStatColumn(
                              'Losses', losses, AppColors.text)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _buildDailyStatColumn(
                              'Trades', trades, AppColors.text)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildDailyStatColumn(
                              'Commissions', comm, AppColors.text)),
                    ]),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tickers
                          .map((t) =>
                              _buildTickerPill(t, context, dayData))
                          .toList(),
                    ),
                    if (savedNote != null && savedNote.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(color: Color(0xFF222222), height: 1),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () =>
                            _showDailyNoteEditor(date, savedNote),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.sticky_note_2_outlined,
                                  color: AppColors.dim, size: 14),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  savedNote,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Color(0xFF999999),
                                      fontSize: 13,
                                      height: 1.4),
                                ),
                              ),
                            ]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _buildActionButton(
                  icon: Icons.edit_note_rounded,
                  label: savedNote != null && savedNote.isNotEmpty
                      ? 'Edit Note'
                      : 'Add Note',
                  color: AppColors.blue,
                  onTap: () =>
                      _showDailyNoteEditor(date, savedNote ?? ''),
                ),
                const SizedBox(width: 10),
                _buildActionButton(
                  icon: Icons.receipt_long_outlined,
                  label: 'View Trades',
                  color: AppColors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DailyDetailScreen(dayData: dayData, onTagsUpdated: fetchJournalData)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  void _showDailyNoteEditor(String date, String initialNote) {
    final ctrl = TextEditingController(text: initialNote);
    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daily Notes',
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(date,
                                style: TextStyle(
                                    color: AppColors.dim, fontSize: 12)),
                          ]),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setSheet(() => isSaving = true);
                                await _saveDailyNote(
                                    date, ctrl.text.trim());
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.blue))
                            : const Text('Save',
                                style: TextStyle(
                                    color: AppColors.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                      ),
                    ]),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  maxLines: 7,
                  autofocus: true,
                  style:
                      TextStyle(color: AppColors.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText:
                        'Market conditions, mistakes, lessons, plan for tomorrow...',
                    hintStyle:
                        const TextStyle(color: Color(0xFF444444)),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Future<void> _saveDailyNote(String date, String note) async {
    try {
      await http.post(
        Uri.parse('$kBaseUrl/api/daily_notes/$date'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'note': note}),
      );
      setState(() => _dailyNotes[date] = note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.red),
      );
    }
  }

  Widget _buildDailyStatColumn(
      String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                TextStyle(color: AppColors.dim, fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTickerPill(Map<String, dynamic> t, BuildContext ctx,
      Map<String, dynamic> dayData) {
    final String name = t['name'] as String;
    final bool isWin = t['win'] as bool;
    final List<dynamic> trades = t['trades'] as List? ?? [];
    final Color bg = isWin ? AppColors.green : AppColors.red;

    return GestureDetector(
      onTap: () {
        if (trades.isEmpty) return;
        Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => DailyDetailScreen(
                  dayData: dayData, focusSymbol: name, onTagsUpdated: fetchJournalData),
            ));
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          if (trades.isNotEmpty) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: Colors.white70, size: 12),
          ],
        ]),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ]),
      ),
    );
  }

  // ================= 📈 Monthly 视图 =================

  Widget _buildMonthlyItem(
      String monthYear,
      String profit,
      String wins,
      String avgGain,
      List<dynamic> rawChartData,
      bool isProfitMonth,
      int cardIndex) {
    List<FlSpot> spots = [];
    double minY = 0.0, maxY = 0.0;
    for (int i = 0; i < rawChartData.length; i++) {
      double val =
          (rawChartData[i]['value'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), val));
      if (val < minY) minY = val;
      if (val > maxY) maxY = val;
    }
    double range = maxY - minY;
    if (range == 0) range = 10;
    double topPadding = maxY + (range * 0.15);
    double bottomPadding = minY - (range * 0.15);

    final bool isThisCardTouched =
        touchedMonthlyIndex == cardIndex;
    final String displayProfit =
        isThisCardTouched && touchedProfitValue != null
            ? touchedProfitValue!
            : profit;
    final Color displayProfitColor =
        isThisCardTouched && touchedProfitRaw != null
            ? (touchedProfitRaw! > 0
                ? AppColors.green
                : touchedProfitRaw! < 0
                    ? AppColors.red
                    : AppColors.text)
            : (isProfitMonth ? AppColors.green : AppColors.red);

    return GestureDetector(
      onTap: () {
        if (_wasDraggingOnChart) return;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  MonthlyDetailScreen(monthYear: monthYear)),
        );
      },
      child: Container(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(monthYear,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text)),
                    if (isThisCardTouched && touchedDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(touchedDate!,
                            style: TextStyle(
                                color: AppColors.dim, fontSize: 13)),
                      ),
                  ],
                ),
                Icon(Icons.chevron_right,
                    color: AppColors.text, size: 28),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMonthlyStat(
                    'Profit', displayProfit, displayProfitColor),
                _buildMonthlyStat('Wins (%)', wins, AppColors.text),
                _buildMonthlyStat(
                    'Avg gain (%)', avgGain, AppColors.text),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 120,
              width: double.infinity,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (spots.length - 1).toDouble(),
                  minY: bottomPadding,
                  maxY: topPadding,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    getTouchedSpotIndicator:
                        (LineChartBarData barData,
                            List<int> spotIndexes) {
                      return spotIndexes.map((index) {
                        return TouchedSpotIndicatorData(
                          FlLine(
                              color: AppColors.text.withValues(alpha: 0.38),
                              strokeWidth: 1.5,
                              dashArray: [4, 4]),
                          FlDotData(
                            show: true,
                            getDotPainter:
                                (spot, percent, barData, index) =>
                                    FlDotCirclePainter(
                              radius: 5,
                              color: AppColors.text,
                              strokeWidth: 2,
                              strokeColor: AppColors.blue,
                            ),
                          ),
                        );
                      }).toList();
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) =>
                          touchedSpots
                              .map((spot) => null)
                              .toList(),
                    ),
                    touchCallback: (FlTouchEvent event,
                        LineTouchResponse? touchResponse) {
                      if (!event.isInterestedForInteractions ||
                          touchResponse == null ||
                          touchResponse.lineBarSpots == null) {
                        setState(() {
                          touchedMonthlyIndex = null;
                          touchedDate = null;
                          touchedProfitValue = null;
                          touchedProfitRaw = null;
                        });
                        Future.delayed(Duration.zero, () {
                          if (mounted) {
                            setState(() {
                              _wasDraggingOnChart = false;
                              _chartDragEventCount = 0;
                            });
                          }
                        });
                        return;
                      }
                      _chartDragEventCount++;
                      if (_chartDragEventCount >= 3) {
                        _wasDraggingOnChart = true;
                      }
                      final int index = touchResponse
                          .lineBarSpots!.first.spotIndex;
                      final double pnl =
                          touchResponse.lineBarSpots!.first.y;
                      setState(() {
                        touchedMonthlyIndex = cardIndex;
                        touchedProfitRaw = pnl;
                        if (index >= 0 &&
                            index < rawChartData.length) {
                          touchedDate =
                              rawChartData[index]['date'];
                        }
                        final String formatted =
                            NumberFormatter.format(pnl.abs());
                        touchedProfitValue = pnl == 0
                            ? '\$0.00'
                            : '${pnl > 0 ? '+' : '-'}\$$formatted';
                      });
                    },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.red,
                          AppColors.blue,
                          AppColors.green,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.green.withValues(alpha: 0.12),
                            AppColors.blue.withValues(alpha: 0.04),
                            AppColors.red.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyStat(
      String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.dim, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ================= 📅 Calendar 视图 =================

  int _monthStringToInt(String month) {
    const m = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
      'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
      'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    };
    return m[month.substring(0, 3)] ?? 1;
  }

  double _parsePnl(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

  int _pnlLevel(double amount, List<double> thr) {
    if (thr.isEmpty || amount <= 0) return 1;
    if (amount <= thr[0]) return 1;
    if (amount <= thr[1]) return 2;
    if (amount <= thr[2]) return 3;
    if (amount <= thr[3]) return 4;
    return 5;
  }

  Color _heatColor(bool isProfit, int level) {
    const greens = [
      Color(0xFF0D2318), Color(0xFF133520), Color(0xFF1D5430),
      Color(0xFF258A42), Color(0xFF30D158),
    ];
    const reds = [
      Color(0xFF2A100F), Color(0xFF3E1615), Color(0xFF5E1F1E),
      Color(0xFF922A29), Color(0xFFFF453A),
    ];
    final idx = (level - 1).clamp(0, 4);
    return isProfit ? greens[idx] : reds[idx];
  }

  List<double> _thresholds(List<double> values) {
    if (values.isEmpty) return [0, 0, 0, 0];
    final s = List<double>.from(values)..sort();
    double p(double pct) =>
        s[(s.length * pct).floor().clamp(0, s.length - 1)];
    return [p(0.2), p(0.4), p(0.6), p(0.8)];
  }

  Widget _buildDynamicCalendarList() {
    if (dailyData.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.calendar_today_outlined,
        title: 'No records',
        subtitle:
            'Your trading calendar will populate after syncing.',
      );
    }

    final Map<String, dynamic> dayMap = {
      for (final d in dailyData) d['date'] as String: d
    };

    final profits = dailyData
        .where((d) => d['isProfit'] == true)
        .map((d) => _parsePnl(d['pnl'] as String))
        .toList();
    final losses = dailyData
        .where((d) => d['isProfit'] == false)
        .map((d) => _parsePnl(d['pnl'] as String))
        .toList();
    final profitThr = _thresholds(profits);
    final lossThr = _thresholds(losses);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildYearHeatmap(dayMap, profitThr, lossThr),
          const SizedBox(height: 12),
          _buildHeatmapLegend(),
          const SizedBox(height: 32),
          ...monthlyData.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: _buildCalendarMonth(
                    m['monthYear'] as String, dayMap, profitThr, lossThr),
              )),
        ],
      ),
    );
  }

  Widget _buildYearHeatmap(Map<String, dynamic> dayMap,
      List<double> profitThr, List<double> lossThr) {
    const cellSz = 11.0;
    const gap = 2.0;
    const step = cellSz + gap;

    final allDates =
        dayMap.keys.map(DateTime.parse).toList()..sort();
    if (allDates.isEmpty) return const SizedBox.shrink();

    DateTime start = allDates.first;
    start = start.subtract(Duration(days: start.weekday - 1));
    DateTime end = DateTime.now();
    end = end.add(Duration(days: 7 - end.weekday));

    final weeks = <List<DateTime>>[];
    DateTime cursor = start;
    while (!cursor.isAfter(end)) {
      final week = <DateTime>[];
      for (int d = 0; d < 7; d++) {
        week.add(cursor.add(Duration(days: d)));
      }
      weeks.add(week);
      cursor = cursor.add(const Duration(days: 7));
    }

    final monthLabels = <int, String>{};
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    int? lastMonth;
    for (int i = 0; i < weeks.length; i++) {
      final m = weeks[i].first.month;
      if (m != lastMonth) {
        monthLabels[i] = monthNames[m - 1];
        lastMonth = m;
      }
    }

    final totalWidth = weeks.length * step;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth + 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 18,
                  child: Stack(
                    children: monthLabels.entries.map((e) {
                      return Positioned(
                        left: 28 + e.key * step,
                        child: Text(e.value,
                            style: TextStyle(
                                color: AppColors.dim,
                                fontSize: 11)),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: List.generate(7, (i) {
                        final label = i == 0
                            ? 'Mon'
                            : i == 2
                                ? 'Wed'
                                : i == 4
                                    ? 'Fri'
                                    : '';
                        return SizedBox(
                          height: step,
                          width: 26,
                          child: Text(label,
                              style: TextStyle(
                                  color: AppColors.dimDark,
                                  fontSize: 9)),
                        );
                      }),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: weeks.map((week) {
                        return Padding(
                          padding: const EdgeInsets.only(right: gap),
                          child: Column(
                            children: week.map((date) {
                              final key =
                                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                              final d = dayMap[key];
                              final isFuture =
                                  date.isAfter(DateTime.now());
                              return _buildHeatCell(
                                date: date,
                                dayData: d,
                                isFuture: isFuture,
                                size: cellSz,
                                gap: gap,
                                profitThr: profitThr,
                                lossThr: lossThr,
                              );
                            }).toList(),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeatCell({
    required DateTime date,
    required dynamic dayData,
    required bool isFuture,
    required double size,
    required double gap,
    required List<double> profitThr,
    required List<double> lossThr,
  }) {
    Color color;
    if (isFuture || date.weekday == 6 || date.weekday == 7) {
      color = const Color(0xFF0D0F12);
    } else if (dayData == null) {
      color = AppColors.surface2;
    } else {
      final isProfit = dayData['isProfit'] as bool;
      final amount = _parsePnl(dayData['pnl'] as String);
      final thr = isProfit ? profitThr : lossThr;
      final level = _pnlLevel(amount, thr);
      color = _heatColor(isProfit, level);
    }
    return GestureDetector(
      onTap: dayData == null ? null : () => _showDayTooltip(dayData),
      child: Container(
        width: size,
        height: size,
        margin: EdgeInsets.only(bottom: gap),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }

  void _showDayTooltip(dynamic dayData) {
    final bool isProfit = dayData['isProfit'] as bool;
    final String pnl = dayData['pnl'] as String;
    final String date = dayData['date'] as String;
    final String trades = dayData['trades'] as String;
    final String winPct = dayData['winPct'] as String;
    final pnlColor = isProfit ? AppColors.green : AppColors.red;
    final sign = isProfit ? '+' : '-';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(date,
              style: TextStyle(
                  color: AppColors.dim, fontSize: 14)),
          const SizedBox(height: 8),
          Text('$sign$pnl',
              style: TextStyle(
                  color: pnlColor,
                  fontSize: 42,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _tooltipStat('Trades', trades),
                Container(
                    width: 1,
                    height: 36,
                    color: AppColors.border),
                _tooltipStat('Win Rate', winPct),
              ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DailyDetailScreen(dayData: dayData, onTagsUpdated: fetchJournalData)));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: const Text('View Day Detail',
                    style: TextStyle(
                        color: AppColors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tooltipStat(String label, String value) =>
      Column(children: [
        Text(value,
            style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(color: AppColors.dim, fontSize: 12)),
      ]);

  Widget _buildHeatmapLegend() {
    const greens = [
      Color(0xFF0D2318), Color(0xFF133520), Color(0xFF1D5430),
      Color(0xFF258A42), Color(0xFF30D158),
    ];
    const reds = [
      Color(0xFFFF453A), Color(0xFF922A29), Color(0xFF5E1F1E),
      Color(0xFF3E1615), Color(0xFF2A100F),
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text('Loss',
          style: TextStyle(color: AppColors.dimDark, fontSize: 11)),
      const SizedBox(width: 6),
      ...reds.map((c) => Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2)),
          )),
      Container(
        width: 11,
        height: 11,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(2)),
      ),
      ...greens.map((c) => Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2)),
          )),
      const SizedBox(width: 4),
      Text('Profit',
          style: TextStyle(color: AppColors.dimDark, fontSize: 11)),
    ]);
  }

  Widget _buildCalendarMonth(String monthYearStr,
      Map<String, dynamic> dayMap,
      List<double> profitThr,
      List<double> lossThr) {
    final parts = monthYearStr.split(',');
    final mName = parts[0].trim();
    final year = int.parse(parts[1].trim());
    final month = _monthStringToInt(mName);
    final first = DateTime(year, month, 1);
    final days = DateTime(year, month + 1, 0).day;
    final empty = first.weekday == 7 ? 0 : first.weekday;

    double monthPnl = 0;
    int monthWins = 0, monthTotal = 0;
    for (int d = 1; d <= days; d++) {
      final key =
          '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final dd = dayMap[key];
      if (dd == null) continue;
      monthPnl += (dd['isProfit'] as bool ? 1 : -1) *
          _parsePnl(dd['pnl'] as String);
      monthTotal += int.tryParse(dd['trades'] as String) ?? 0;
      if (dd['isProfit'] == true) monthWins++;
    }
    final tradingDays = dailyData.where((d) {
      final date = d['date'] as String;
      return date
          .startsWith('$year-${month.toString().padLeft(2, '0')}');
    }).length;
    final winRate = tradingDays > 0
        ? (monthWins / tradingDays * 100).round()
        : 0;
    final pnlColor =
        monthPnl >= 0 ? AppColors.green : AppColors.red;
    final pnlStr = monthPnl >= 0
        ? '+\$${monthPnl.toStringAsFixed(2)}'
        : '-\$${monthPnl.abs().toStringAsFixed(2)}';

    final cells = <Widget>[
      for (int i = 0; i < empty; i++) const SizedBox(),
      for (int day = 1; day <= days; day++)
        Builder(builder: (_) {
          final key =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final dd = dayMap[key];
          return _buildMonthCell(day, dd, profitThr, lossThr);
        }),
    ];

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(monthYearStr,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text)),
                Text(pnlStr,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: pnlColor)),
              ]),
          const SizedBox(height: 4),
          Text('$monthTotal trades · $winRate% win rate',
              style: const TextStyle(
                  color: Color(0xFF666666), fontSize: 12)),
          const SizedBox(height: 12),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _WeekLabel('Sun'),
                _WeekLabel('Mon'),
                _WeekLabel('Tue'),
                _WeekLabel('Wed'),
                _WeekLabel('Thu'),
                _WeekLabel('Fri'),
                _WeekLabel('Sat'),
              ]),
          const SizedBox(height: 6),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 1.0,
            children: cells,
          ),
        ]);
  }

  Widget _buildMonthCell(int day, dynamic dayData,
      List<double> profitThr, List<double> lossThr) {
    if (dayData == null) {
      return Container(
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(4),
        child: Text('$day',
            style: const TextStyle(
                color: Color(0xFF333333), fontSize: 11)),
      );
    }
    final isProfit = dayData['isProfit'] as bool;
    final amount = _parsePnl(dayData['pnl'] as String);
    final thr = isProfit ? profitThr : lossThr;
    final level = _pnlLevel(amount, thr);
    final bg = _heatColor(isProfit, level);
    final textColor = level >= 4
        ? Colors.black.withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.7);
    return GestureDetector(
      onTap: () => _showDayTooltip(dayData),
      child: Container(
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(4),
        child: Text('$day',
            style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// 星期表头小组件
class _WeekLabel extends StatelessWidget {
  final String text;
  const _WeekLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style:
          TextStyle(color: AppColors.dimDark, fontSize: 11));
}
