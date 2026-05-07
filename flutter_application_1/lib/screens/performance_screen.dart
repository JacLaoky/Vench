import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/utils.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});
  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  bool isLoading = true;
  bool hasError = false;
  String selectedTimeframe = '1M';
  final List<String> allTimeframes = ['1W', '1M', '3M', '1Y', 'YTD', 'AT'];

  // ── summary ───────────────────────────────────────
  double totalPnl = 0; int tradeCount = 0; String winRate = '0%';
  double profitFactor = 0; double expectancy = 0;
  double avgWin = 0; double avgLoss = 0; double winLossRatio = 0;
  double maxDrawdown = 0;
  int maxWinStreak = 0; int maxLossStreak = 0;
  int currentStreak = 0; String currentStreakType = 'W';

  double sharpeRatio  = 0;
  double sortinoRatio = 0;
  double kellyPct     = 0;

  // ── charts & deep stats ───────────────────────────
  List<dynamic> monthlyBars   = [];
  List<dynamic> dowStats      = [];
  List<dynamic> drawdownCurve = [];
  Map<String, dynamic>? deepStats;

  // ── chart touch state ─────────────────────────────
  int? _touchedIdx;

  @override
  void initState() {
    super.initState();
    _loadPrefsAndFetch();
  }

  Future<void> _loadPrefsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('performance_timeframe');
    if (saved != null) setState(() => selectedTimeframe = saved);
    fetchPerformance();
  }

  Future<void> fetchPerformance() async {
    setState(() { isLoading = true; hasError = false; });
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/api/performance?period=$selectedTimeframe'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'empty') {
          setState(() { isLoading = false; tradeCount = 0; });
          return;
        }
        final s = data['summary'];
        setState(() {
          totalPnl          = (s['total_pnl']          as num).toDouble();
          tradeCount        = s['trade_count']          as int;
          winRate           = s['win_rate'];
          profitFactor      = (s['profit_factor']       as num).toDouble();
          expectancy        = (s['expectancy']           as num).toDouble();
          avgWin            = (s['avg_win']              as num).toDouble();
          avgLoss           = (s['avg_loss']             as num).toDouble();
          winLossRatio      = (s['win_loss_ratio']       as num).toDouble();
          maxDrawdown       = (s['max_drawdown']         as num).toDouble();
          maxWinStreak      = s['max_win_streak']        as int;
          maxLossStreak     = s['max_loss_streak']       as int;
          currentStreak     = s['current_streak']        as int;
          currentStreakType = s['current_streak_type'];
          monthlyBars       = data['monthly_bars']       ?? [];
          dowStats          = data['dow_stats']          ?? [];
          drawdownCurve     = data['drawdown_curve']     ?? [];
          deepStats         = data['deep_stats'] != null
              ? Map<String, dynamic>.from(data['deep_stats'])
              : null;
          sharpeRatio  = (s['sharpe_ratio']  as num? ?? 0).toDouble();
          sortinoRatio = (s['sortino_ratio'] as num? ?? 0).toDouble();
          kellyPct     = (s['kelly_pct']     as num? ?? 0).toDouble();
          isLoading         = false;
        });
      }
    } catch (e) {
      debugPrint('Performance error: $e');
      setState(() { isLoading = false; hasError = true; });
    }
  }

  String get timeLabel {
    return timeLabelFor(selectedTimeframe);
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: isLoading
          ? _buildSkeleton()
          : hasError
              ? ErrorRetryWidget(
                  message: 'Could not reach the server.\nMake sure your backend is running.',
                  onRetry: fetchPerformance,
                )
              : RefreshIndicator(
                  color: AppColors.blue,
                  backgroundColor: AppColors.card,
                  onRefresh: () => fetchPerformance(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Period selector is ALWAYS visible so user can switch timeframes
                        const SizedBox(height: 16),
                        _buildPeriodSelector(),
                        const SizedBox(height: 16),

                        // Empty state — only the content area, selector stays above
                        if (tradeCount == 0)
                          const SizedBox(
                            height: 400,
                            child: EmptyStateWidget(
                              icon: Icons.insights_outlined,
                              title: 'No data yet',
                              subtitle: 'No trades in this period.\nTry a different timeframe.',
                            ),
                          )
                        else ...[
                          const SizedBox(height: 12),
                          _buildSectionHeader('Key Metrics'),
                          const SizedBox(height: 14),
                          _buildMetricsGrid(),
                          const SizedBox(height: 28),
                          _buildSectionHeader('Streaks'),
                          const SizedBox(height: 14),
                          _buildStreakRow(),
                          const SizedBox(height: 28),
                          _buildSectionHeader('Risk Metrics'),
                          const SizedBox(height: 14),
                          _buildRiskMetrics(),
                          if (drawdownCurve.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _buildSectionHeader('Equity & Drawdown'),
                            const SizedBox(height: 14),
                            _buildDrawdownChart(),
                          ],
                          if (monthlyBars.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _buildSectionHeader('Monthly P&L'),
                            const SizedBox(height: 14),
                            _buildMonthlyChart(),
                          ],
                          if (dowStats.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _buildSectionHeader('P&L by Day of Week'),
                            const SizedBox(height: 14),
                            _buildDowChart(),
                          ],
                          if (deepStats != null) ...[
                            const SizedBox(height: 36),
                            _buildDeepStatsSection(),
                          ],
                          const SizedBox(height: 60),
                        ],
                      ],
                    ),    // Column
                  ),      // SingleChildScrollView
                ),        // RefreshIndicator
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const ShimmerBox(height: 40, radius: 10),
          const SizedBox(height: 28),
          const ShimmerBox(height: 22, width: 130, radius: 6),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            const ShimmerBox(height: 80),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 28),
          const ShimmerBox(height: 22, width: 100, radius: 6),
          const SizedBox(height: 14),
          const ShimmerBox(height: 70),
          const SizedBox(height: 28),
          const ShimmerBox(height: 200),
        ],
      ),
    );
  }

  // ─── Risk Metrics ────────────────────────────────────────────
  Widget _buildRiskMetrics() {
    Color _riskColor(double v, {double good = 1.0, double warn = 0.0}) {
      if (v >= good)  return AppColors.green;
      if (v >= warn)  return AppColors.orange;
      return AppColors.red;
    }

    String _fmt(double v) => v == 0 ? '—' : v.toStringAsFixed(2);

    return Column(children: [
      // ── 三个指标卡 ─────────────────────────────────────────
      Row(children: [
        Expanded(child: _riskCard(
          label: 'Sharpe Ratio',
          value: _fmt(sharpeRatio),
          color: _riskColor(sharpeRatio),
          tooltip: '> 1 = good\n> 2 = great',
        )),
        const SizedBox(width: 10),
        Expanded(child: _riskCard(
          label: 'Sortino Ratio',
          value: _fmt(sortinoRatio),
          color: _riskColor(sortinoRatio),
          tooltip: 'Downside-only\nrisk adjustment',
        )),
        const SizedBox(width: 10),
        Expanded(child: _riskCard(
          label: 'Kelly %',
          value: kellyPct == 0 ? '—' : '${kellyPct.toStringAsFixed(1)}%',
          color: _riskColor(kellyPct, good: 10, warn: 0),
          tooltip: 'Optimal position\nsize per trade',
        )),
      ]),
      const SizedBox(height: 10),
      // ── 最大回撤单独一行（更显眼）──────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.arrow_downward_rounded,
                color: AppColors.red, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Max Drawdown',
                style: TextStyle(color: AppColors.dim, fontSize: 13)),
            const SizedBox(height: 3),
            Text(
              maxDrawdown == 0 ? '—' : '-\$${maxDrawdown.abs().toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.red,
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('from peak', style: TextStyle(color: AppColors.dimDark, fontSize: 11)),
            const SizedBox(height: 4),
            Text(timeLabel, style: TextStyle(color: AppColors.dimDark, fontSize: 11)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _riskCard({
    required String label,
    required String value,
    required Color color,
    required String tooltip,
  }) {
    return GestureDetector(
      onLongPress: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: $tooltip'),
            backgroundColor: AppColors.surface2,
            duration: const Duration(seconds: 2)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: AppColors.dim, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(color: color,
                  fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  // ─── Equity + Drawdown chart ─────────────────────────────────
  Widget _buildDrawdownChart() {
    if (drawdownCurve.isEmpty) return const SizedBox.shrink();

    final equitySpots   = <FlSpot>[];
    final drawdownSpots = <FlSpot>[];
    double minDD = 0, maxEq = 0, minEq = 0;

    for (int i = 0; i < drawdownCurve.length; i++) {
      final pt  = drawdownCurve[i];
      final eq  = (pt['equity']   as num).toDouble();
      final dd  = (pt['drawdown'] as num).toDouble();
      equitySpots.add(FlSpot(i.toDouble(), eq));
      drawdownSpots.add(FlSpot(i.toDouble(), dd));
      if (eq > maxEq) maxEq = eq;
      if (eq < minEq) minEq = eq;
      if (dd < minDD) minDD = dd;
    }

    final maxX = (drawdownCurve.length - 1).toDouble();

    int maxDdIdx = 0;
    double worstDd = 0;
    for (int i = 0; i < drawdownSpots.length; i++) {
      if (drawdownSpots[i].y < worstDd) {
        worstDd = drawdownSpots[i].y;
        maxDdIdx = i;
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 图例 ─────────────────────────────────────────────
        Row(children: [
          _ddLegend(AppColors.blue, 'Equity curve'),
          const SizedBox(width: 16),
          _ddLegend(AppColors.red, 'Drawdown'),
          const Spacer(),
          if (worstDd < 0)
            Text(
              'Max DD  -\$${worstDd.abs().toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.red,
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ]),
        const SizedBox(height: 20),

        // ── 权益曲线 ─────────────────────────────────────────
        SizedBox(
          height: 130,
          child: LineChart(LineChartData(
            minX: 0, maxX: maxX,
            minY: minEq * 1.1,
            maxY: maxEq * 1.1,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            // ── 触摸：显示日期 + 累计盈亏 ──
            lineTouchData: LineTouchData(
              enabled: true,
              touchCallback: (event, response) {
                final idx = response?.lineBarSpots?.firstOrNull?.x.toInt();
                if (idx != null) {
                  setState(() => _touchedIdx = idx);
                } else if (event.isInterestedForInteractions == false) {
                  setState(() => _touchedIdx = null);
                }
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.darkBg,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                getTooltipItems: (spots) {
                  final idx = spots.first.x.toInt().clamp(0, drawdownCurve.length - 1);
                  final date = drawdownCurve[idx]['date'] as String;
                  final eq   = spots.first.y;
                  final isPos = eq >= 0;
                  final ddVal = (drawdownCurve[idx]['drawdown'] as num).toDouble();
                  return [
                    LineTooltipItem(
                      '$date\n',
                      TextStyle(color: AppColors.dim, fontSize: 11),
                      children: [
                        TextSpan(
                          text: '${isPos ? '+' : ''}\$${eq.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isPos ? AppColors.green : AppColors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (ddVal < 0)
                          TextSpan(
                            text: '   DD -\$${ddVal.abs().toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ];
                },
              ),
            ),
            // ── 同步竖线：当回撤区触摸时，权益曲线也显示标记 ──
            extraLinesData: _touchedIdx != null
                ? ExtraLinesData(verticalLines: [
                    VerticalLine(
                      x: _touchedIdx!.toDouble(),
                      color: AppColors.dim.withValues(alpha: 0.25),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ])
                : null,
            lineBarsData: [
              LineChartBarData(
                spots: equitySpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.blue,
                barWidth: 2,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) =>
                      spot.x == maxX || spot.x == _touchedIdx?.toDouble(),
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: spot.x == _touchedIdx?.toDouble() ? 5 : 4,
                    color: AppColors.blue,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.blue.withValues(alpha: 0.06),
                ),
              ),
            ],
          )),
        ),

        const SizedBox(height: 6),
        const Divider(color: Color(0xFF222222), height: 1),
        const SizedBox(height: 6),

        // ── 回撤曲线（倒置，红色填充）───────────────────────
        SizedBox(
          height: 80,
          child: LineChart(LineChartData(
            minX: 0, maxX: maxX,
            minY: minDD * 1.2,
            maxY: 0,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: minDD != 0 ? (minDD * 1.2).abs() / 3 : 1,
              getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF222222), strokeWidth: 0.5),
            ),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: maxX > 0 ? maxX / 4 : 1,
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt().clamp(0, drawdownCurve.length - 1);
                    return Text(
                      drawdownCurve[idx]['date'] as String,
                      style: TextStyle(color: AppColors.dimDark, fontSize: 9),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            // ── 触摸：同步 _touchedIdx，显示日期 + 回撤值 ──
            lineTouchData: LineTouchData(
              enabled: true,
              touchCallback: (event, response) {
                final idx = response?.lineBarSpots?.firstOrNull?.x.toInt();
                if (idx != null) {
                  setState(() => _touchedIdx = idx);
                } else if (event.isInterestedForInteractions == false) {
                  setState(() => _touchedIdx = null);
                }
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.darkBg,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                getTooltipItems: (spots) {
                  final idx = spots.first.x.toInt().clamp(0, drawdownCurve.length - 1);
                  final date = drawdownCurve[idx]['date'] as String;
                  return [
                    LineTooltipItem(
                      '$date\n',
                      TextStyle(color: AppColors.dim, fontSize: 11),
                      children: [
                        TextSpan(
                          text: '-\$${spots.first.y.abs().toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ];
                },
              ),
            ),
            // ── 同步竖线：当权益区触摸时，回撤曲线也显示标记 ──
            extraLinesData: _touchedIdx != null
                ? ExtraLinesData(verticalLines: [
                    VerticalLine(
                      x: _touchedIdx!.toDouble(),
                      color: AppColors.dim.withValues(alpha: 0.25),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ])
                : null,
            lineBarsData: [
              LineChartBarData(
                spots: drawdownSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.red,
                barWidth: 1.5,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) =>
                      spot.x == maxDdIdx.toDouble() ||
                      spot.x == _touchedIdx?.toDouble(),
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: spot.x == _touchedIdx?.toDouble() ? 5 : 4,
                    color: AppColors.red,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.red.withValues(alpha: 0.15),
                ),
              ),
            ],
          )),
        ),
      ]),
    );
  }

  Widget _ddLegend(Color color, String label) => Row(children: [
    Container(width: 20, height: 2,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: AppColors.dim, fontSize: 12)),
  ]);

  // ─── Period selector ─────────────────────────────────────────
  Widget _buildPeriodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: allTimeframes.map((tf) {
          final sel = selectedTimeframe == tf;
          return GestureDetector(
            onTap: () {
              if (!sel) {
                setState(() => selectedTimeframe = tf);
                SharedPreferences.getInstance().then((p) => p.setString('performance_timeframe', tf));
                fetchPerformance();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? AppColors.border : AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(tf,
                style: TextStyle(
                  color: sel ? AppColors.text : AppColors.dim,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Section header ──────────────────────────────────────────
  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(title,
        style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
  );

  // ─── 3×3 metrics grid ────────────────────────────────────────
  Widget _buildMetricsGrid() {
    final p      = totalPnl >= 0;
    final pnlClr = p ? AppColors.green : AppColors.red;
    final pfStr  = profitFactor >= 999 ? '∞' : profitFactor.toStringAsFixed(2);
    final sign   = totalPnl >= 0 ? '+' : '-';
    final pnlStr = '$sign\$${NumberFormatter.format(totalPnl.abs())}';
    final expStr = '${expectancy >= 0 ? '+' : '-'}\$${expectancy.abs().toStringAsFixed(2)}';
    final ddStr  = maxDrawdown == 0 ? '\$0.00' : '-\$${maxDrawdown.abs().toStringAsFixed(2)}';

    final metrics = [
      {'label': 'Net P&L',       'value': pnlStr,                              'color': pnlClr},
      {'label': 'Win Rate',      'value': winRate,                              'color': AppColors.text},
      {'label': 'Total Trades',  'value': tradeCount.toString(),               'color': AppColors.text},
      {'label': 'Profit Factor', 'value': pfStr,
        'color': profitFactor >= 1.0 ? AppColors.green : AppColors.red},
      {'label': 'Expectancy',    'value': expStr,
        'color': expectancy >= 0     ? AppColors.green : AppColors.red},
      {'label': 'Win/Loss Ratio','value': winLossRatio.toStringAsFixed(2),
        'color': winLossRatio >= 1.0 ? AppColors.green : AppColors.text},
      {'label': 'Avg Win',       'value': '\$${avgWin.toStringAsFixed(2)}',    'color': AppColors.green},
      {'label': 'Avg Loss',      'value': '-\$${avgLoss.toStringAsFixed(2)}',  'color': AppColors.red},
      {'label': 'Max Drawdown',  'value': ddStr,                               'color': AppColors.red},
    ];

    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.25),
      itemCount: metrics.length,
      itemBuilder: (_, i) {
        final m = metrics[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(m['label'] as String,
                style: TextStyle(color: AppColors.dim, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(m['value'] as String,
                style: TextStyle(color: m['color'] as Color, fontSize: 15, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  // ─── Streaks ─────────────────────────────────────────────────
  Widget _buildStreakRow() {
    final clr    = currentStreakType == 'W' ? AppColors.green : AppColors.red;
    final lbl    = currentStreakType == 'W' ? 'Win' : 'Loss';
    return Row(children: [
      Expanded(child: _streakCard('Current Streak', '$currentStreak $lbl', clr)),
      const SizedBox(width: 10),
      Expanded(child: _streakCard('Best Win Streak',     maxWinStreak.toString(),  AppColors.green)),
      const SizedBox(width: 10),
      Expanded(child: _streakCard('Worst Loss Streak',   maxLossStreak.toString(), AppColors.red)),
    ]);
  }

  Widget _streakCard(String label, String value, Color valueColor) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: AppColors.dim, fontSize: 11)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
    ]),
  );

  // ─── Monthly bar chart ────────────────────────────────────────
  Widget _buildMonthlyChart() {
    final bars = monthlyBars.length > 12
        ? monthlyBars.sublist(monthlyBars.length - 12)
        : monthlyBars;
    double maxAbs = 1.0;
    for (var b in bars) {
      final v = (b['value'] as num).toDouble().abs();
      if (v > maxAbs) maxAbs = v;
    }
    return Container(
      height: 220,
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 6, right: 6),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY:  maxAbs * 1.35, minY: -maxAbs * 1.35,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final b = bars[group.x];
              final v = (b['value'] as num).toDouble();
              return BarTooltipItem(
                '${b['label']}\n${v >= 0 ? '+' : ''}\$${v.toStringAsFixed(0)}',
                TextStyle(color: AppColors.text, fontSize: 12));
            }),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (val, _) {
              final i = val.toInt();
              if (i < 0 || i >= bars.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text((bars[i]['label'] as String).split(' ').first,
                    style: TextStyle(color: AppColors.dim, fontSize: 10)));
            },
          )),
        ),
        barGroups: List.generate(bars.length, (i) {
          final v  = (bars[i]['value'] as num).toDouble();
          final ip = bars[i]['isProfit'] as bool;
          final c  = ip ? AppColors.green : AppColors.red;
          return BarChartGroupData(x: i, barRods: [BarChartRodData(
            toY: v, color: c, width: 14,
            borderRadius: ip
                ? const BorderRadius.vertical(top:    Radius.circular(4))
                : const BorderRadius.vertical(bottom: Radius.circular(4)),
          )]);
        }),
      )),
    );
  }

  // ─── Day-of-week bars ─────────────────────────────────────────
  Widget _buildDowChart() {
    double maxAbs = 1.0;
    for (var d in dowStats) {
      final v = (d['pnl'] as num).toDouble().abs();
      if (v > maxAbs) maxAbs = v;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: dowStats.map((d) {
          final label   = d['label']    as String;
          final pnl     = (d['pnl']     as num).toDouble();
          final trades  = d['trades']   as int;
          final wr      = (d['win_rate']as num).toDouble();
          final isP     = pnl >= 0;
          final barFrac = trades == 0 ? 0.0 : (pnl.abs() / maxAbs).clamp(0.0, 1.0);
          final barClr  = isP ? AppColors.green : AppColors.red;
          final sign    = pnl >= 0 ? '+' : '-';
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              SizedBox(width: 36,
                child: Text(label, style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600))),
              Expanded(child: LayoutBuilder(builder: (ctx, c) => Stack(children: [
                Container(height: 30, decoration: BoxDecoration(color: AppColors.darkBg, borderRadius: BorderRadius.circular(6))),
                Container(height: 30, width: c.maxWidth * barFrac,
                  decoration: BoxDecoration(color: barClr.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(6))),
                Positioned.fill(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(trades == 0 ? 'No trades' : '$trades trades  ${(wr * 100).toStringAsFixed(0)}% WR',
                        style: TextStyle(color: AppColors.dim, fontSize: 11)),
                    Text(trades == 0 ? '--' : '$sign\$${pnl.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                          color: trades == 0 ? AppColors.dimDark : barClr,
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                )),
              ]))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ─── Deep Stats section ───────────────────────────────────────
  Widget _buildDeepStatsSection() {
    final gl = deepStats!['gain_loss']  as Map;
    final ls = deepStats!['long_short'] as Map;
    final tm = deepStats!['timing']     as Map;
    final bw = deepStats!['best_worst'] as Map;
    final symTrades = deepStats!['symbols_by_trades'] as List? ?? [];
    final symAmount = deepStats!['symbols_by_amount'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Gain / Loss ──────────────────────────────────────────
        _statCard(
          icon: Icons.bar_chart_rounded,
          iconColor: AppColors.blue,
          title: 'Gain / Loss',
          child: Column(children: [
            _statTableHeader(),
            _statRow('Total',     gl['total']['all'],   gl['total']['won'],   gl['total']['lost'],   colored: true),
            _statRow('Avg in \$', gl['avg_usd']['all'], gl['avg_usd']['won'], gl['avg_usd']['lost'], colored: true),
            _statRow('Avg in %',  gl['avg_pct']['all'], gl['avg_pct']['won'], gl['avg_pct']['lost'], colored: true),
            _statRow('Trades',    gl['trades']['all'],  gl['trades']['won'],  gl['trades']['lost']),
            Divider(color: AppColors.border, height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Win Rate', style: TextStyle(color: AppColors.dim, fontSize: 13)),
              Text(gl['win_rate'], style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Long vs Short ────────────────────────────────────────
        _statCard(
          icon: Icons.compare_arrows_rounded,
          iconColor: AppColors.orange,
          title: 'Long / Short',
          child: Column(children: [
            _statTableHeader(),
            _statRow('Long Trades',  ls['long']['all'],  ls['long']['won'],  ls['long']['lost']),
            _statRow('Short Trades', ls['short']['all'], ls['short']['won'], ls['short']['lost']),
            const SizedBox(height: 4),
            _buildLongShortBar(
              int.tryParse(ls['long']['all']  ?? '0') ?? 0,
              int.tryParse(ls['short']['all'] ?? '0') ?? 0,
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Timing ───────────────────────────────────────────────
        _statCard(
          icon: Icons.timer_outlined,
          iconColor: AppColors.purple,
          title: 'Timing',
          child: Column(children: [
            _statTableHeader(),
            _statRow('Avg Hold Time',   tm['holding']['all'],    tm['holding']['won'],    tm['holding']['lost']),
            _statRow('Avg Entry Hour',  tm['entry_hour']['all'], tm['entry_hour']['won'], tm['entry_hour']['lost']),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Best / Worst ─────────────────────────────────────────
        _statCard(
          icon: Icons.emoji_events_outlined,
          iconColor: AppColors.yellow,
          title: 'Best / Worst Trade',
          child: Column(children: [
            _bestWorstHeader(),
            _bestWorstRow('Largest \$', bw['largest_usd']['won'], bw['largest_usd']['lost']),
            _bestWorstRow('Largest %', bw['largest_pct']['won'], bw['largest_pct']['lost']),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Symbols ──────────────────────────────────────────────
        if (symTrades.isNotEmpty) ...[
          _statCard(
            icon: Icons.stacked_bar_chart_rounded,
            iconColor: AppColors.green,
            title: 'Trades by Symbol',
            child: Column(children: [
              _statTableHeader(),
              ...symTrades.take(8).map((s) =>
                _statRow(s['symbol'], s['trades']['all'], s['trades']['won'], s['trades']['lost'])),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        if (symAmount.isNotEmpty)
          _statCard(
            icon: Icons.attach_money_rounded,
            iconColor: AppColors.green,
            title: 'P&L by Symbol',
            child: Column(children: [
              ...symAmount.take(8).map((s) {
                final pnlRaw = (s['pnl_raw'] as num).toDouble();
                final isP    = s['isProfit'] as bool;
                final pnlClr = isP ? AppColors.green : AppColors.red;
                final pnlStr = '${isP ? '+' : ''}\$${pnlRaw.abs().toStringAsFixed(2)}';
                return _symbolPnlRow(s['symbol'] as String, pnlStr, pnlClr,
                    '${s['trades']['all']} trades');
              }),
            ]),
          ),
      ],
    );
  }

  // ─── Shared deep-stats sub-widgets ───────────────────────────
  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBg, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 18),
        child,
      ]),
    );
  }

  Widget _statTableHeader() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      const Expanded(flex: 4, child: SizedBox()),
      Expanded(flex: 3, child: Text('All',  textAlign: TextAlign.right, style: TextStyle(color: AppColors.dimDark, fontSize: 11, letterSpacing: 0.5))),
      Expanded(flex: 3, child: Text('Won',  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.green, fontSize: 11, letterSpacing: 0.5))),
      Expanded(flex: 3, child: Text('Lost', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.red, fontSize: 11, letterSpacing: 0.5))),
    ]),
  );

  Widget _statRow(String label, String all, String won, String lost, {bool colored = false}) {
    Color wonClr  = colored ? AppColors.green : AppColors.text;
    Color lostClr = colored ? AppColors.red : AppColors.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        Expanded(flex: 4, child: Text(label, style: TextStyle(color: AppColors.dim, fontSize: 13))),
        Expanded(flex: 3, child: Text(all,  textAlign: TextAlign.right, style: TextStyle(color: AppColors.text,            fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Text(won,  textAlign: TextAlign.right, style: TextStyle(color: wonClr,  fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Text(lost, textAlign: TextAlign.right, style: TextStyle(color: lostClr, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _bestWorstHeader() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: const [
      Expanded(flex: 4, child: SizedBox()),
      Expanded(flex: 3, child: Text('Best',  textAlign: TextAlign.right, style: TextStyle(color: AppColors.green, fontSize: 11, letterSpacing: 0.5))),
      Expanded(flex: 3, child: Text('Worst', textAlign: TextAlign.right, style: TextStyle(color: AppColors.red, fontSize: 11, letterSpacing: 0.5))),
    ]),
  );

  Widget _bestWorstRow(String label, String best, String worst) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(children: [
      Expanded(flex: 4, child: Text(label, style: TextStyle(color: AppColors.dim, fontSize: 13))),
      Expanded(flex: 3, child: Text(best,  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w600))),
      Expanded(flex: 3, child: Text(worst, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );

  // Long vs Short 视觉分割条
  Widget _buildLongShortBar(int longAll, int shortAll) {
    final total = longAll + shortAll;
    if (total == 0) return const SizedBox();
    final longFrac  = longAll  / total;
    final shortFrac = shortAll / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Flexible(
            flex: (longFrac  * 1000).round(),
            child: Container(height: 8, color: AppColors.blue),
          ),
          const SizedBox(width: 2),
          Flexible(
            flex: (shortFrac * 1000).round(),
            child: Container(height: 8, color: AppColors.orange),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _barLegend(AppColors.blue, 'Long  ${(longFrac * 100).toStringAsFixed(0)}%'),
        const SizedBox(width: 16),
        _barLegend(AppColors.orange, 'Short  ${(shortFrac * 100).toStringAsFixed(0)}%'),
      ]),
    ]);
  }

  Widget _barLegend(Color color, String text) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(text, style: TextStyle(color: AppColors.dim, fontSize: 11)),
  ]);

  // Symbol P&L row (for Amount by Symbol)
  Widget _symbolPnlRow(String symbol, String pnlStr, Color pnlColor, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            symbol.isNotEmpty ? symbol[0] : '?',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(symbol, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle, style: TextStyle(color: AppColors.dim, fontSize: 11)),
        ])),
        Text(pnlStr, style: TextStyle(color: pnlColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
