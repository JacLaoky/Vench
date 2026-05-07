import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

// ================= 📂 Position Detail Screen =================
// Handles two entry paths:
//   1. Holdings (open position):  positionId=null, live market data provided
//   2. AllTradesScreen (closed):  positionId set, live data all null
class OpenPositionScreen extends StatefulWidget {
  final String  ticker;
  final String? positionId;   // set when navigating from AllTradesScreen

  // Live market data — only available when coming from Holdings
  final String? name;
  final double? marketVal;
  final double? plVal;
  final double? plRatio;
  final double? todayPnl;
  final double? qty;
  final double? costPrice;

  const OpenPositionScreen({
    super.key,
    required this.ticker,
    this.positionId,
    this.name,
    this.marketVal,
    this.plVal,
    this.plRatio,
    this.todayPnl,
    this.qty,
    this.costPrice,
  });

  @override
  State<OpenPositionScreen> createState() => _OpenPositionScreenState();
}

class _OpenPositionScreenState extends State<OpenPositionScreen> {
  bool _isLoading = true;
  bool _hasError  = false;
  List<dynamic> _trades = [];

  // Fields from backend response
  double?  _backendTotalPnl;
  double?  _backendEntryPrice;
  double?  _backendStopPrice;
  double?  _rMultiple;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final pid = widget.positionId;
      final uri = pid != null
          ? Uri.parse('$kBaseUrl/api/holdings/${widget.ticker}/trades?position_id=$pid')
          : Uri.parse('$kBaseUrl/api/holdings/${widget.ticker}/trades');

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final d = json.decode(res.body);
        setState(() {
          _trades            = d['data']        as List?   ?? [];
          _backendTotalPnl   = (d['total_pnl']   as num?)?.toDouble();
          _backendEntryPrice = (d['entry_price']  as num?)?.toDouble();
          _backendStopPrice  = (d['stop_price']   as num?)?.toDouble();
          _rMultiple         = (d['r_multiple']   as num?)?.toDouble();
          _isLoading         = false;
        });
      } else {
        setState(() { _isLoading = false; _hasError = true; });
      }
    } catch (_) {
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  String _fmt(double v, {bool sign = false}) {
    final s = sign ? (v >= 0 ? '+' : '-') : (v < 0 ? '-' : '');
    final abs = v.abs();
    if (abs >= 1_000_000) return '$s\$${(abs / 1_000_000).toStringAsFixed(2)}M';
    if (abs >= 1_000)     return '$s\$${(abs / 1_000).toStringAsFixed(1)}K';
    return '$s\$${abs.toStringAsFixed(2)}';
  }

  Map<String, List<dynamic>> _groupByPid() {
    final groups = <String, List<dynamic>>{};
    for (final t in _trades) {
      final pid = (t['position_id'] as String?) ?? '__solo__';
      groups.putIfAbsent(pid, () => []).add(t);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        title: Text(widget.ticker,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _hasError
              ? ErrorRetryWidget(message: 'Could not load trades.', onRetry: _fetch)
              : RefreshIndicator(
                  color: AppColors.blue,
                  backgroundColor: AppColors.card,
                  onRefresh: _fetch,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: _buildHeader(),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                          child: Text('TRADE HISTORY',
                              style: TextStyle(
                                  color: AppColors.dim,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      if (_trades.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text('No trade records found',
                                  style: TextStyle(color: AppColors.dim, fontSize: 14)),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final groups = _groupByPid();
                                final pid    = groups.keys.toList()[i];
                                return _PositionGroup(
                                  positionId: pid,
                                  trades:     groups[pid]!,
                                );
                              },
                              childCount: _groupByPid().length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    final isOpenPosition = widget.marketVal != null;  // came from Holdings

    if (isOpenPosition) {
      // ── Open position: show live Moomoo data ──
      final plVal    = widget.plVal!;
      final plRatio  = widget.plRatio!;
      final todayPnl = widget.todayPnl!;
      final pnlColor   = plVal   >= 0 ? AppColors.green : AppColors.red;
      final todayColor = todayPnl >= 0 ? AppColors.green : AppColors.red;
      final pctStr = '${plVal >= 0 ? '+' : ''}${plRatio.toStringAsFixed(2)}%';
      final curPrice = (widget.qty ?? 0) > 0
          ? widget.marketVal! / widget.qty!
          : 0.0;

      return _HeaderCard(children: [
        _HeaderTopRow(
          ticker:   widget.ticker,
          name:     widget.name ?? widget.ticker,
          rMultiple: _rMultiple,
          rightTop: _fmt(widget.marketVal!),
          rightSub: 'Market Value',
        ),
        const SizedBox(height: 14),
        Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 14),
        Row(children: [
          _Stat('Shares',   '${(widget.qty ?? 0).toInt()}'),
          _Stat('Avg Cost', '\$${(widget.costPrice ?? 0).toStringAsFixed(2)}'),
          _Stat('Now',      '\$${curPrice.toStringAsFixed(2)}'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _Stat('Unrealized', '${_fmt(plVal, sign: true)}  $pctStr', color: pnlColor),
          _Stat('Today',      _fmt(todayPnl, sign: true),             color: todayColor),
        ]),
        if (_backendStopPrice != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.flag_outlined, size: 13, color: AppColors.dim),
            const SizedBox(width: 4),
            Text('Stop \$${_backendStopPrice!.toStringAsFixed(2)}',
                style: TextStyle(color: AppColors.dim, fontSize: 12)),
          ]),
        ],
      ]);
    } else {
      // ── Closed position: show realized P&L from trades ──
      final totalPnl   = _backendTotalPnl ?? 0.0;
      final pnlColor   = totalPnl >= 0 ? AppColors.green : AppColors.red;

      return _HeaderCard(children: [
        _HeaderTopRow(
          ticker:    widget.ticker,
          name:      widget.name ?? widget.ticker,
          rMultiple: _rMultiple,
          rightTop:  _fmt(totalPnl, sign: true),
          rightSub:  'Realized P&L',
          rightColor: pnlColor,
        ),
        if (_backendEntryPrice != null || _backendStopPrice != null) ...[
          const SizedBox(height: 14),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(children: [
            if (_backendEntryPrice != null)
              _Stat('Avg Entry', '\$${_backendEntryPrice!.toStringAsFixed(2)}'),
            if (_backendStopPrice != null)
              _Stat('Stop', '\$${_backendStopPrice!.toStringAsFixed(2)}'),
          ]),
        ],
      ]);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared header widgets
// ─────────────────────────────────────────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final List<Widget> children;
  const _HeaderCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _HeaderTopRow extends StatelessWidget {
  final String  ticker, name, rightTop, rightSub;
  final double? rMultiple;
  final Color?  rightColor;
  const _HeaderTopRow({
    required this.ticker,
    required this.name,
    required this.rightTop,
    required this.rightSub,
    this.rMultiple,
    this.rightColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ticker,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(name,
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
              if (rMultiple != null) ...[
                const SizedBox(height: 6),
                _RBadge(r: rMultiple!),
              ],
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rightTop,
                style: TextStyle(
                    color: rightColor ?? AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(rightSub,
                style: TextStyle(color: AppColors.dim, fontSize: 11)),
          ]),
        ],
      );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.dim, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// R multiple badge
// ─────────────────────────────────────────────────────────────────────────────
class _RBadge extends StatelessWidget {
  final double r;
  const _RBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    final color = r >= 0 ? AppColors.green : AppColors.red;
    final label = '${r > 0 ? '+' : ''}${r.toStringAsFixed(2)}R';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Position group (collapsible)
// ─────────────────────────────────────────────────────────────────────────────
class _PositionGroup extends StatefulWidget {
  final String positionId;
  final List<dynamic> trades;
  const _PositionGroup({required this.positionId, required this.trades});

  @override
  State<_PositionGroup> createState() => _PositionGroupState();
}

class _PositionGroupState extends State<_PositionGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                ),
                child: Text(widget.positionId,
                    style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Text('${widget.trades.length} orders',
                  style: TextStyle(color: AppColors.dim, fontSize: 11)),
              const Spacer(),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.dim, size: 18,
              ),
            ]),
          ),
        ),
        if (_expanded) ...widget.trades.map((t) => _TradeRow(trade: t)),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual trade row
// ─────────────────────────────────────────────────────────────────────────────
class _TradeRow extends StatelessWidget {
  final dynamic trade;
  const _TradeRow({required this.trade});

  @override
  Widget build(BuildContext context) {
    final action  = trade['action'] as String;
    final price   = (trade['price']         as num).toDouble();
    final qty     = (trade['qty']           as num).toDouble();
    final day     = trade['day']   as String;
    final month   = trade['month'] as String;
    final time    = trade['time']  as String;
    final pnl     = (trade['realized_pnl']  as num).toDouble();

    final isBuy   = action == 'BUY' || action == 'BUY_BACK';
    final actionColor = isBuy ? AppColors.green : AppColors.red;
    final actionLabel = isBuy ? 'BUY' : 'SELL';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(children: [
        // Date
        SizedBox(
          width: 32,
          child: Column(children: [
            Text(day,   style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
            Text(month, style: TextStyle(color: AppColors.dim, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 12),

        // Action badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: actionColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(actionLabel,
              style: TextStyle(
                  color: actionColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),

        // Price × qty + time
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('\$${price.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
            Text('${qty.toInt()} shares  ·  $time',
                style: TextStyle(color: AppColors.dim, fontSize: 11)),
          ]),
        ),

        // Realized P&L (only for SELL rows with non-zero pnl)
        if (!isBuy && pnl != 0)
          Text(
            '${pnl > 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
            style: TextStyle(
                color: pnl >= 0 ? AppColors.green : AppColors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }
}
