import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/trade_card_widget.dart';

// ── Helper: group trades by position_id, preserving order ──
List<List<dynamic>> _groupByPosition(List<dynamic> trades) {
  final groups = <String, List<dynamic>>{};
  final order = <String>[];
  for (final t in trades) {
    final pid = (t['position_id'] as String?) ?? '__none__${t['trade_id']}';
    if (!groups.containsKey(pid)) {
      groups[pid] = [];
      order.add(pid);
    }
    groups[pid]!.add(t);
  }
  return order.map((k) => groups[k]!).toList();
}

// ================= 📅 单日交易流水页 =================
class DailyDetailScreen extends StatefulWidget {
  final dynamic dayData;
  final String? focusSymbol; // 来自 pill 点击，自动滚动到该 symbol
  final VoidCallback? onTagsUpdated;

  const DailyDetailScreen({
    super.key,
    required this.dayData,
    this.focusSymbol,
    this.onTagsUpdated,
  });

  @override
  State<DailyDetailScreen> createState() => _DailyDetailScreenState();
}

class _DailyDetailScreenState extends State<DailyDetailScreen> {
  final Map<String, GlobalKey> _symbolKeys = {};
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.focusSymbol != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToSymbol(widget.focusSymbol!));
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToSymbol(String symbol) {
    final key = _symbolKeys[symbol];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final String dateStr = widget.dayData['date'] as String;
    final String weekday = widget.dayData['weekday'] as String;
    final String pnl = widget.dayData['pnl'] as String;
    final bool isProfit = widget.dayData['isProfit'] as bool;
    final String winPct = widget.dayData['winPct'] as String;
    final String wins = widget.dayData['wins'] as String;
    final String losses = widget.dayData['losses'] as String;
    final List<dynamic> tickers = widget.dayData['tickers'] ?? [];

    final pnlColor = isProfit ? AppColors.green : AppColors.red;
    final pnlStr = isProfit ? '+$pnl' : '-$pnl';

    for (final t in tickers) {
      final name = t['name'] as String;
      _symbolKeys.putIfAbsent(name, () => GlobalKey());
    }

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.darkBg,
            elevation: 0,
            pinned: true,
            expandedHeight: 140,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: AppColors.text),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$weekday · $dateStr',
                        style: TextStyle(
                            color: AppColors.dim, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(pnlStr,
                          style: TextStyle(
                              color: pnlColor,
                              fontSize: 30,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      _miniPill('$wins W', AppColors.green),
                      const SizedBox(width: 6),
                      _miniPill('$losses L', AppColors.red),
                      const SizedBox(width: 6),
                      _miniPill(winPct, AppColors.text),
                    ]),
                  ],
                ),
              ),
              title: Text('$weekday · $dateStr',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
            ),
          ),
          if (tickers.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text('No closed trades this day',
                    style: TextStyle(color: Color(0xFF666666))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final t = tickers[i];
                    final name = t['name'] as String;
                    final isWin = t['win'] as bool;
                    final trades = t['trades'] as List? ?? [];
                    final key = _symbolKeys[name]!;
                    final isFocus = widget.focusSymbol == name;

                    return Padding(
                      key: key,
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: isFocus ? 4 : 0,
                              height: 20,
                              margin:
                                  EdgeInsets.only(right: isFocus ? 8 : 0),
                              decoration: BoxDecoration(
                                color: isWin ? AppColors.green : AppColors.red,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Text(name,
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isWin
                                        ? AppColors.green
                                        : AppColors.red)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${trades.length} trade${trades.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: isWin ? AppColors.green : AppColors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          if (trades.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text('No closed trades',
                                  style: TextStyle(
                                      color: AppColors.dimDark, fontSize: 13)),
                            )
                          else
                            ..._buildPositionGroups(trades),
                        ],
                      ),
                    );
                  },
                  childCount: tickers.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Position grouping ─────────────────────────────────────────────────────

  List<Widget> _buildPositionGroups(List<dynamic> trades) {
    final groups = _groupByPosition(trades);
    final multiGroup = groups.length > 1;
    final widgets = <Widget>[];

    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (!multiGroup) {
        // Only 1 position for this ticker → render cards directly, no extra header
        for (final trade in group) {
          widgets.add(TradeCardWidget(
            trade: trade,
            onTagsUpdated: widget.onTagsUpdated,
          ));
        }
      } else {
        // Multiple positions under same ticker → show position header for each
        widgets.add(_PositionGroupCard(
          positionIndex: i + 1,
          trades: group,
          onTagsUpdated: widget.onTagsUpdated,
        ));
      }
    }
    return widgets;
  }

  Widget _miniPill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ── Position Group Card ───────────────────────────────────────────────────────
class _PositionGroupCard extends StatefulWidget {
  final int positionIndex;
  final List<dynamic> trades;
  final VoidCallback? onTagsUpdated;

  const _PositionGroupCard({
    required this.positionIndex,
    required this.trades,
    this.onTagsUpdated,
  });

  @override
  State<_PositionGroupCard> createState() => _PositionGroupCardState();
}

class _PositionGroupCardState extends State<_PositionGroupCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    // Sum all realized P&L in this position group
    double totalPnl = 0;
    for (final t in widget.trades) {
      totalPnl += (t['pnl'] as num).toDouble();
    }
    final isProfit = totalPnl >= 0;
    final pnlColor = isProfit ? AppColors.green : AppColors.red;
    final pnlStr = totalPnl == 0
        ? '\$0.00'
        : '${totalPnl > 0 ? '+' : '-'}\$${totalPnl.abs().toStringAsFixed(2)}';

    final orderCount = widget.trades.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Position header row ──
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.6),
            ),
            child: Row(
              children: [
                // Position badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Position #${widget.positionIndex}',
                    style: const TextStyle(
                      color: AppColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Order count chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Text(
                    '$orderCount order${orderCount == 1 ? '' : 's'}',
                    style: TextStyle(color: AppColors.dim, fontSize: 11),
                  ),
                ),
                const Spacer(),
                // P&L
                Text(
                  pnlStr,
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                // Chevron
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.dim, size: 18),
                ),
              ],
            ),
          ),
        ),
        // ── Expandable trade cards ──
        AnimatedCrossFade(
          firstChild: Column(
            children: widget.trades
                .map((t) => TradeCardWidget(
                      trade: t,
                      onTagsUpdated: widget.onTagsUpdated,
                    ))
                .toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
