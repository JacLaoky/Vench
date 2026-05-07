import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';
import 'package:flutter_application_1/screens/open_position_screen.dart';

class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({super.key});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<dynamic> _positions = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final res = await http.get(Uri.parse('$kBaseUrl/api/portfolio'));
      if (res.statusCode == 200) {
        final d = json.decode(res.body);
        setState(() {
          _positions = d['data'] as List? ?? [];
          _isLoading = false;
        });
      } else {
        setState(() { _isLoading = false; _hasError = true; });
      }
    } catch (_) {
      setState(() { _isLoading = false; _hasError = true; });
    }
  }

  // ── Summary totals ──────────────────────────────────────────────────────────
  double get _totalValue   => _positions.fold(0, (s, p) => s + (p['market_val'] as num));
  double get _totalPnl     => _positions.fold(0, (s, p) => s + (p['pl_val']     as num));
  double get _todayPnl     => _positions.fold(0, (s, p) => s + (p['today_pl_val'] as num));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        title: const Text('Holdings', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _hasError
              ? ErrorRetryWidget(
                  message: 'Could not load positions.\nMake sure the backend is running.',
                  onRetry: _fetch,
                )
              : _positions.isEmpty
                  ? Center(
                      child: Text('No open positions',
                          style: TextStyle(color: AppColors.dim, fontSize: 16)),
                    )
                  : RefreshIndicator(
                      color: AppColors.blue,
                      backgroundColor: AppColors.card,
                      onRefresh: _fetch,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildSummary()),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => _HoldingCard(position: _positions[i]),
                                childCount: _positions.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSummary() {
    final pnlColor   = _totalPnl  >= 0 ? AppColors.green : AppColors.red;
    final todayColor = _todayPnl  >= 0 ? AppColors.green : AppColors.red;

    String fmt(double v, {bool sign = false}) {
      final s = sign ? (v >= 0 ? '+' : '-') : (v < 0 ? '-' : '');
      final abs = v.abs();
      if (abs >= 1000000) return '$s\$${(abs / 1000000).toStringAsFixed(2)}M';
      if (abs >= 1000)    return '$s\$${(abs / 1000).toStringAsFixed(1)}K';
      return '$s\$${abs.toStringAsFixed(2)}';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Market value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Market Value',
                    style: TextStyle(color: AppColors.dim, fontSize: 11)),
                const SizedBox(height: 4),
                Text(fmt(_totalValue),
                    style: TextStyle(
                        color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Divider
          Container(width: 0.5, height: 36, color: AppColors.border),
          const SizedBox(width: 16),
          // P&L column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(children: [
                Text('Unrealized  ', style: TextStyle(color: AppColors.dim, fontSize: 11)),
                Text(fmt(_totalPnl, sign: true),
                    style: TextStyle(color: pnlColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('Today  ', style: TextStyle(color: AppColors.dim, fontSize: 11)),
                Text(fmt(_todayPnl, sign: true),
                    style: TextStyle(color: todayColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual position card
// ─────────────────────────────────────────────────────────────────────────────
class _HoldingCard extends StatelessWidget {
  final dynamic position;
  const _HoldingCard({required this.position});

  void _refreshParent(BuildContext context) {
    // Walk up to HoldingsScreen and trigger a refresh
    final state = context.findAncestorStateOfType<_HoldingsScreenState>();
    state?._fetch();
  }

  void _showSetStopDialog(
    BuildContext context,
    String positionId,
    String ticker,
    double? current, {
    VoidCallback? onSaved,
  }) {
    final ctrl = TextEditingController(
        text: current != null ? current.toStringAsFixed(2) : '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Stop Price — $ticker',
            style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'e.g. 350.00',
            hintStyle: TextStyle(color: AppColors.dim),
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: AppColors.dim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.dim)),
          ),
          TextButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                await http.patch(
                  Uri.parse('$kBaseUrl/api/positions/$positionId/stop'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'stop_price': val, 'ticker': ticker}),
                );
                if (context.mounted) Navigator.pop(context);
                onSaved?.call();
              }
            },
            child: const Text('Save',
                style: TextStyle(color: AppColors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticker     = position['ticker']       as String;
    final name       = position['name']         as String;
    final qty        = (position['qty']         as num).toDouble();
    final cost       = (position['cost_price']  as num).toDouble();
    final mktVal     = (position['market_val']  as num).toDouble();
    final plVal      = (position['pl_val']      as num).toDouble();
    final plRatio    = (position['pl_ratio']    as num).toDouble();
    final todayPnl   = (position['today_pl_val'] as num).toDouble();
    final isShort    = (position['side'] as String).toUpperCase().contains('SHORT');
    final stopPrice  = (position['stop_price']  as num?)?.toDouble();
    final positionId = position['position_id']  as String?;

    final isProfit  = plVal >= 0;
    final pnlColor  = isProfit ? AppColors.green : AppColors.red;
    final todayColor = todayPnl >= 0 ? AppColors.green : AppColors.red;
    final pnlSign   = plVal > 0 ? '+' : '';
    final todaySign = todayPnl > 0 ? '+' : '';
    final pctStr    = '${plVal >= 0 ? '+' : ''}${plRatio.toStringAsFixed(2)}%';

    // Current price ≈ market_val / qty
    final curPrice = qty > 0 ? mktVal / qty : 0.0;

    // Unrealized R = (cur - entry) / (entry - stop)
    double? rMultiple;
    if (stopPrice != null && stopPrice > 0 && cost > 0 && curPrice > 0) {
      final risk = (cost - stopPrice).abs();
      if (risk > 0.001) {
        rMultiple = (curPrice - cost) / (cost - stopPrice);
      }
    }

    final initial = ticker.isNotEmpty ? ticker[0] : '?';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OpenPositionScreen(
            ticker:     ticker,
            positionId: positionId,
            name:       name,
            marketVal:  mktVal,
            plVal:      plVal,
            plRatio:    plRatio,
            todayPnl:   todayPnl,
            qty:        qty,
            costPrice:  cost,
          ),
        ),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.5),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Accent strip
              Container(
                width: 3,
                color: isProfit ? AppColors.green : AppColors.red,
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFFF7A00),
                        child: Text(initial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                      const SizedBox(width: 12),

                      // Ticker / name / qty
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(ticker,
                                    style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.dim, fontSize: 12)),
                                ),
                                if (isShort)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.red.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('SHORT',
                                        style: TextStyle(
                                            color: AppColors.red,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${qty.toInt()} shares  ·  avg \$${cost.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: AppColors.dim, fontSize: 11),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Now \$${curPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // P&L + R column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '\$${mktVal.toStringAsFixed(0)}',
                            style: TextStyle(
                                color: AppColors.text,
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$pnlSign\$${plVal.abs().toStringAsFixed(2)}  $pctStr',
                            style: TextStyle(
                                color: pnlColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Today $todaySign\$${todayPnl.abs().toStringAsFixed(2)}',
                            style: TextStyle(color: todayColor, fontSize: 11),
                          ),
                          if (rMultiple != null) ...[
                            const SizedBox(height: 4),
                            _RBadge(r: rMultiple),
                          ],
                          const SizedBox(height: 4),
                          if (stopPrice != null)
                            GestureDetector(
                              onTap: () => _showSetStopDialog(
                                  context, positionId!, ticker, stopPrice,
                                  onSaved: () => _refreshParent(context)),
                              child: Text(
                                'Stop \$${stopPrice.toStringAsFixed(2)} ✎',
                                style: TextStyle(
                                    color: AppColors.dim, fontSize: 10),
                              ),
                            )
                          else if (positionId != null)
                            GestureDetector(
                              onTap: () => _showSetStopDialog(
                                  context, positionId, ticker, null,
                                  onSaved: () => _refreshParent(context)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: AppColors.blue.withValues(alpha: 0.3),
                                      width: 0.5),
                                ),
                                child: const Text('Set Stop',
                                    style: TextStyle(
                                        color: AppColors.blue,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ), // Container
    ); // GestureDetector
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _RBadge extends StatelessWidget {
  final double r;
  const _RBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    final color = r >= 0 ? AppColors.green : AppColors.red;
    final label = '${r > 0 ? '+' : ''}${r.toStringAsFixed(2)}R';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
