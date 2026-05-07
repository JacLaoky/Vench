import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/trade_card_widget.dart';
import 'package:flutter_application_1/screens/open_position_screen.dart';

// ── Group trades by position_id (preserving order) ───────────────────────────
List<List<dynamic>> _groupByPosition(List<dynamic> trades) {
  final groups = <String, List<dynamic>>{};
  final order  = <String>[];
  for (final t in trades) {
    final pid = (t['position_id'] as String?) ?? '__solo__${t['trade_id']}';
    if (!groups.containsKey(pid)) {
      groups[pid] = [];
      order.add(pid);
    }
    groups[pid]!.add(t);
  }
  return order.map((k) => groups[k]!).toList();
}

// ================= 📜 全部交易列表页 (All Trades) =================
class AllTradesScreen extends StatefulWidget {
  const AllTradesScreen({super.key});

  @override
  State<AllTradesScreen> createState() => _AllTradesScreenState();
}

class _AllTradesScreenState extends State<AllTradesScreen> {
  bool isLoading = true;
  List<dynamic> allTrades = [];

  // ── 搜索 ──────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── 过滤器状态 ────────────────────────────────────────────
  String _pnlFilter  = 'all'; // 'all' | 'win' | 'loss'
  String _sideFilter = 'all'; // 'all' | 'long' | 'short'
  String _sortMode   = 'date_desc';
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    fetchAllTrades();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchAllTrades() async {
    try {
      final response = await http.get(Uri.parse('$kBaseUrl/api/all_trades'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() { allTrades = data['data']; isLoading = false; });
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // ── Core: per-position grouped + filtered + sorted ────────────────────────
  List<List<dynamic>> get _filteredPositions {
    // Step 1: group all trades into positions first
    final allGroups = _groupByPosition(allTrades);

    // Step 2: filter at position level
    var result = allGroups.where((group) {
      final totalPnl = group.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());

      // 2a. Symbol search: any order in group matches
      if (_searchQuery.isNotEmpty) {
        final matches = group.any((t) =>
            (t['ticker'] as String).toLowerCase().contains(_searchQuery));
        if (!matches) return false;
      }

      // 2b. P&L filter: based on position total P&L
      if (_pnlFilter == 'win'  && totalPnl <= 0) return false;
      if (_pnlFilter == 'loss' && totalPnl >= 0) return false;

      // 2c. Side filter: first order's trade_type represents the position direction
      if (_sideFilter != 'all') {
        final type = (group.first['trade_type'] as String).toUpperCase();
        if (_sideFilter == 'long'  && type != 'LONG')  return false;
        if (_sideFilter == 'short' && type != 'SHORT') return false;
      }

      // 2d. Date range: any order in group falls within range
      if (_dateRange != null) {
        final inRange = group.any((t) {
          try {
            final month = t['month'] as String;
            final day   = int.tryParse(t['day'] as String) ?? 1;
            const monthMap = {
              'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,
              'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12,
            };
            final now  = DateTime.now();
            final m    = monthMap[month] ?? now.month;
            var d = DateTime(now.year, m, day);
            if (d.isAfter(now)) d = DateTime(now.year - 1, m, day);
            return !d.isBefore(_dateRange!.start) && !d.isAfter(_dateRange!.end);
          } catch (_) { return true; }
        });
        if (!inRange) return false;
      }

      return true;
    }).toList();

    // Step 3: sort (by first order's index in allTrades, or by P&L)
    switch (_sortMode) {
      case 'pnl_desc':
        result.sort((a, b) {
          final pa = a.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());
          final pb = b.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());
          return pb.compareTo(pa);
        });
        break;
      case 'pnl_asc':
        result.sort((a, b) {
          final pa = a.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());
          final pb = b.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());
          return pa.compareTo(pb);
        });
        break;
      case 'date_asc':
        result = result.reversed.toList();
        break;
      default: // date_desc: backend already returns newest first
        break;
    }

    return result;
  }

  bool get _hasActiveFilters =>
      _pnlFilter != 'all' || _sideFilter != 'all' || _dateRange != null;

  void _clearAllFilters() {
    setState(() {
      _pnlFilter  = 'all';
      _sideFilter = 'all';
      _dateRange  = null;
      _searchCtrl.clear();
    });
  }

  Future<void> _pickDateRange() async {
    final now   = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate:   DateTime(2020),
      lastDate:    now,
      initialDateRange: _dateRange ?? DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end:   now,
      ),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary:    Color(0xFF4DA1FF),
            onPrimary:  Colors.white,
            surface:    Color(0xFF13151A),
            onSurface:  Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF13151A)),
        ),
        child: child!,
      ),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Sort by', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...[
            ('date_desc', 'Date — Newest first',  Icons.arrow_downward_rounded),
            ('date_asc',  'Date — Oldest first',  Icons.arrow_upward_rounded),
            ('pnl_desc',  'P&L — Highest first',  Icons.trending_up_rounded),
            ('pnl_asc',   'P&L — Lowest first',   Icons.trending_down_rounded),
          ].map((item) {
            final (mode, label, icon) = item;
            final selected = _sortMode == mode;
            return ListTile(
              leading: Icon(icon, color: selected ? AppColors.blue : AppColors.dim, size: 20),
              title: Text(label, style: TextStyle(
                color: selected ? AppColors.blue : AppColors.dim,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
              trailing: selected ? const Icon(Icons.check, color: Color(0xFF4DA1FF), size: 18) : null,
              onTap: () { setState(() => _sortMode = mode); Navigator.pop(context); },
            );
          }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = _filteredPositions;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('All Trades', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort_rounded,
              color: _sortMode != 'date_desc' ? AppColors.blue : AppColors.dim,
            ),
            tooltip: 'Sort',
            onPressed: _showSortSheet,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF30D158)))
          : Column(children: [
              // ── 搜索栏 ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: AppColors.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search symbol...',
                    hintStyle: const TextStyle(color: Color(0xFF555555)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF555555), size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF555555), size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
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

              // ── 过滤器胶囊行 ──────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(children: [
                  _filterGroup([
                    ('all',  'All'),
                    ('win',  'Win'),
                    ('loss', 'Loss'),
                  ], _pnlFilter, (v) => setState(() => _pnlFilter = v)),

                  const SizedBox(width: 8),

                  _filterGroup([
                    ('all',   'All'),
                    ('long',  'Long'),
                    ('short', 'Short'),
                  ], _sideFilter, (v) => setState(() => _sideFilter = v)),

                  const SizedBox(width: 8),

                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _dateRange != null
                            ? AppColors.blue.withValues(alpha: 0.2)
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _dateRange != null ? AppColors.blue : AppColors.border,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.date_range_outlined,
                          size: 13,
                          color: _dateRange != null ? AppColors.blue : AppColors.dim,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _dateRange != null
                              ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                              : 'Date',
                          style: TextStyle(
                            fontSize: 13,
                            color: _dateRange != null ? AppColors.blue : AppColors.dim,
                            fontWeight: _dateRange != null ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (_dateRange != null) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() => _dateRange = null),
                            child: const Icon(Icons.close, size: 13, color: Color(0xFF4DA1FF)),
                          ),
                        ],
                      ]),
                    ),
                  ),

                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _clearAllFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Clear', style: TextStyle(color: Color(0xFFFF453A), fontSize: 13)),
                      ),
                    ),
                  ],
                ]),
              ),

              // ── 结果统计行（按 position 计算）─────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    positions.isEmpty
                        ? 'No positions'
                        : '${positions.length} position${positions.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
                  ),
                  if (positions.isNotEmpty)
                    _buildResultSummary(positions),
                ]),
              ),

              const Divider(color: Color(0xFF1C1E24), height: 1),

              // ── 交易列表（按 position 分组）──────────────
              Expanded(
                child: positions.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.search_off_rounded, color: Color(0xFF333333), size: 48),
                        const SizedBox(height: 12),
                        const Text('No trades match your filters',
                            style: TextStyle(color: Color(0xFF666666))),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _clearAllFilters,
                          child: const Text('Clear filters',
                              style: TextStyle(color: Color(0xFF4DA1FF))),
                        ),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: positions.length,
                        itemBuilder: (_, i) {
                          final group = positions[i];
                          if (group.length == 1) {
                            return TradeCardWidget(trade: group.first);
                          }
                          return _PositionGroupCard(trades: group);
                        },
                      ),
              ),
            ]),
    );
  }

  // ── 统计行：基于 position 胜率 ────────────────────────────
  Widget _buildResultSummary(List<List<dynamic>> positions) {
    int wins = 0;
    double totalPnl = 0;
    for (final g in positions) {
      final pnl = g.fold<double>(0, (s, t) => s + (t['pnl'] as num).toDouble());
      totalPnl += pnl;
      if (pnl > 0) wins++;
    }
    final winRate = (wins / positions.length * 100).round();
    final pnlColor = totalPnl >= 0 ? AppColors.green : AppColors.red;
    final pnlStr   = totalPnl >= 0
        ? '+\$${totalPnl.toStringAsFixed(2)}'
        : '-\$${totalPnl.abs().toStringAsFixed(2)}';
    return Row(children: [
      Text('$winRate% win', style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
      const SizedBox(width: 8),
      Text(pnlStr, style: TextStyle(color: pnlColor, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _filterGroup(List<(String, String)> options, String current, ValueChanged<String> onTap) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: options.map((item) {
        final (value, label) = item;
        final selected = current == value;
        return GestureDetector(
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color:      selected ? Colors.white : AppColors.dim,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList()),
    );
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day}';
}

// ── Position Group Card ───────────────────────────────────────────────────────
// Shown when multiple close orders share the same position_id
class _PositionGroupCard extends StatefulWidget {
  final List<dynamic> trades;
  const _PositionGroupCard({required this.trades});

  @override
  State<_PositionGroupCard> createState() => _PositionGroupCardState();
}

class _PositionGroupCardState extends State<_PositionGroupCard> {
  bool _expanded = false; // collapsed by default in list view (less noisy)

  @override
  Widget build(BuildContext context) {
    final double totalPnl = widget.trades
        .fold(0.0, (s, t) => s + (t['pnl'] as num).toDouble());
    final bool isProfit  = totalPnl >= 0;
    final Color pnlColor = isProfit ? AppColors.green : AppColors.red;
    final String pnlStr  = totalPnl == 0
        ? '\$0.00'
        : '${totalPnl > 0 ? '+' : '-'}\$${totalPnl.abs().toStringAsFixed(2)}';

    final String ticker    = widget.trades.first['ticker'] as String;
    final String tradeType = widget.trades.first['trade_type'] as String? ?? '';
    final int    orderCnt  = widget.trades.length;
    final double? stopPrice = (widget.trades.first['stop_price'] as num?)?.toDouble();
    final String  initial  = ticker.isNotEmpty ? ticker[0] : '?';

    // Compute combined % (rough: sum pnl / sum trade_value) — show as badge
    final allPcts = widget.trades
        .map((t) => int.tryParse((t['pct'] as String).replaceAll('%','')) ?? 0)
        .toList();
    final avgPct = allPcts.isEmpty ? 0 : (allPcts.reduce((a,b)=>a+b) / allPcts.length).round();

    // Position-level R = Σ(R_i × qty_i) / Σ(qty_i)
    // Weighted average of per-share R across all partial closes
    double? positionR;
    if (stopPrice != null && stopPrice > 0) {
      double weightedRSum = 0;
      double totalQty     = 0;
      for (final t in widget.trades) {
        final entryPrice = (t['entry_price'] as num?)?.toDouble() ?? 0.0;
        final exitPrice  = (t['price']       as num?)?.toDouble() ?? 0.0;
        final qty        = (t['qty']         as num?)?.toDouble() ?? 1.0;
        if (entryPrice > 0 && exitPrice > 0) {
          final riskPerShare = (entryPrice - stopPrice).abs();
          if (riskPerShare > 0.001) {
            final r = (exitPrice - entryPrice) / (entryPrice - stopPrice);
            weightedRSum += r * qty;
            totalQty     += qty;
          }
        }
      }
      if (totalQty > 0) positionR = weightedRSum / totalQty;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15.5),
        child: Column(
          children: [
            // ── Position summary header ──────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left accent strip
                  Container(width: 3, color: isProfit ? AppColors.green : AppColors.red),
                  // Main content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Avatar
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFFF7A00),
                                child: Text(initial,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$ticker $tradeType',
                                        style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    // "N orders · position" label
                                    Row(children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.blue.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          '$orderCnt orders',
                                          style: const TextStyle(
                                              color: AppColors.blue,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.shield_outlined,
                                          color: AppColors.green, size: 13),
                                      const SizedBox(width: 3),
                                      Text('Position',
                                          style: TextStyle(
                                              color: AppColors.text.withValues(alpha: 0.6),
                                              fontSize: 12)),
                                    ]),
                                  ],
                                ),
                              ),
                              // P&L column
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(pnlStr,
                                      style: TextStyle(
                                          color: pnlColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('~$avgPct%',
                                      style: TextStyle(
                                          color: pnlColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  if (positionR != null) ...[
                                    const SizedBox(height: 4),
                                    _RBadge(r: positionR),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          // Stop price row (once, at position level)
                          if (stopPrice != null) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(Icons.flag_outlined,
                                  size: 13, color: AppColors.dim),
                              const SizedBox(width: 4),
                              Text('Stop \$${stopPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: AppColors.dim, fontSize: 12)),
                            ]),
                          ],
                          // Detail + expand/collapse row
                          const SizedBox(height: 10),
                          Row(children: [
                            // → View detail
                            GestureDetector(
                              onTap: () {
                                final pid = widget.trades.first['position_id'] as String?;
                                if (pid == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OpenPositionScreen(
                                      ticker:     ticker,
                                      positionId: pid,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.open_in_new_rounded,
                                        size: 12, color: AppColors.dim),
                                    const SizedBox(width: 4),
                                    Text('Detail',
                                        style: TextStyle(
                                            color: AppColors.dim,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // → Expand/collapse
                            GestureDetector(
                              onTap: () => setState(() => _expanded = !_expanded),
                              child: Row(children: [
                                Text(
                                  _expanded ? 'Hide orders' : 'Show $orderCnt orders',
                                style: const TextStyle(
                                    color: AppColors.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _expanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(Icons.keyboard_arrow_down_rounded,
                                    color: AppColors.blue, size: 16),
                              ),
                            ]),
                          ), // expand GestureDetector
                          ]), // detail+expand Row
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Expandable individual orders ─────────────────────────────────
            AnimatedCrossFade(
              firstChild: Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  children: widget.trades
                      .map((t) => TradeCardWidget(trade: t))
                      .toList(),
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 220),
            ),
          ],
        ),
      ),
    );
  }
}

// ── R multiple badge (local copy matching trade_card_widget.dart) ─────────────
class _RBadge extends StatelessWidget {
  final double r;
  const _RBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    final isPositive = r >= 0;
    final color = isPositive ? AppColors.green : AppColors.red;
    final sign  = r > 0 ? '+' : '';
    final label = '$sign${r.toStringAsFixed(1)}R';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
