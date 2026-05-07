import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

// ================= Tag Analytics Screen =================
class TagStatsScreen extends StatefulWidget {
  const TagStatsScreen({super.key});

  @override
  State<TagStatsScreen> createState() => _TagStatsScreenState();
}

class _TagStatsScreenState extends State<TagStatsScreen> {
  String _timeframe = 'AT';
  static const _timeframes = ['1W', '1M', '3M', '1Y', 'AT'];

  List<dynamic> _data = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/api/tag_stats?timeframe=$_timeframe'),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['status'] == 'success') {
          setState(() {
            _data = body['data'] as List;
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = true;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _onTimeframeChanged(String tf) {
    if (tf == _timeframe) return;
    setState(() => _timeframe = tf);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Tag Analytics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildTimeframeToggle(),
          const SizedBox(height: 12),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ── Timeframe toggle pill ──────────────────────────────────────────
  Widget _buildTimeframeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: _timeframes.map((tf) {
            final sel = tf == _timeframe;
            return Expanded(
              child: GestureDetector(
                onTap: () => _onTimeframeChanged(tf),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.darkBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tf,
                    style: TextStyle(
                      color: sel ? AppColors.text : AppColors.dim,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error) {
      return ErrorRetryWidget(
        message:
            'Could not load tag stats.\nMake sure your backend is running.',
        onRetry: _fetch,
      );
    }
    if (_data.isEmpty) {
      return Center(
        child: Text(
          'No tagged trades yet.\nLong press a trade to add tags.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.dim, fontSize: 15, height: 1.6),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.blue,
      backgroundColor: AppColors.card,
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _data.length,
        itemBuilder: (_, i) => _TagCard(stat: _data[i]),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: const [
        ShimmerBox(height: 160, radius: 14),
        SizedBox(height: 12),
        ShimmerBox(height: 160, radius: 14),
        SizedBox(height: 12),
        ShimmerBox(height: 160, radius: 14),
      ],
    );
  }
}

// ── Per-tag card ─────────────────────────────────────────────────────
class _TagCard extends StatelessWidget {
  final dynamic stat;
  const _TagCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final tag        = stat['tag'] as String;
    final count      = stat['count'] as int;
    final winRate    = (stat['win_rate'] as num).toDouble();
    final totalPnl   = (stat['total_pnl'] as num).toDouble();
    final avgPnl     = (stat['avg_pnl'] as num).toDouble();
    final avgWin     = (stat['avg_win'] as num).toDouble();
    final avgLoss    = (stat['avg_loss'] as num).toDouble();

    final tagColor      = TagColors.forTag(tag);
    final isProfit      = totalPnl >= 0;
    final pnlColor      = isProfit ? AppColors.green : AppColors.red;
    final avgPnlColor   = avgPnl >= 0 ? AppColors.green : AppColors.red;

    // Progress bar color based on win rate
    Color progressColor;
    if (winRate > 60) {
      progressColor = AppColors.green;
    } else if (winRate >= 40) {
      progressColor = AppColors.orange;
    } else {
      progressColor = AppColors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: tag chip + trade count ───────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Tag chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: tagColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count trades',
                style: TextStyle(
                    color: AppColors.dim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Row 2: Win Rate label + bar + pct ──────────────────
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  'Win Rate',
                  style: TextStyle(color: AppColors.dim, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: winRate / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${winRate.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Row 3: Total P&L ────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total P&L',
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
              Text(
                '${isProfit ? '+' : ''}\$${totalPnl.toStringAsFixed(2)}',
                style: TextStyle(
                    color: pnlColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Row 4: Avg per trade ────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avg per trade',
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
              Text(
                '${avgPnl >= 0 ? '+' : ''}\$${avgPnl.toStringAsFixed(2)}',
                style: TextStyle(
                    color: avgPnlColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // ── Row 5: Avg Win | Avg Loss ────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Avg Win',
                        style:
                            TextStyle(color: AppColors.dim, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '+\$${avgWin.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                  width: 1,
                  height: 30,
                  color: AppColors.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Avg Loss',
                          style: TextStyle(
                              color: AppColors.dim, fontSize: 11)),
                      const SizedBox(height: 3),
                      Text(
                        '\$${avgLoss.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
