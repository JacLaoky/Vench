import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

// ======================== 📈 Sector Detail Screen ========================

class SectorDetailScreen extends StatefulWidget {
  final String ticker;
  final String name;
  final double changePct;
  final double price;

  const SectorDetailScreen({
    super.key,
    required this.ticker,
    required this.name,
    required this.changePct,
    required this.price,
  });

  @override
  State<SectorDetailScreen> createState() => _SectorDetailScreenState();
}

class _SectorDetailScreenState extends State<SectorDetailScreen> {
  Map<String, dynamic>? _data;
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
        Uri.parse('$kBaseUrl/api/sector_detail?ticker=${widget.ticker}'),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          setState(() {
            _data = body;
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
        title: Text(
          '${widget.name} (${widget.ticker})',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? _buildSkeleton()
          : _error
              ? ErrorRetryWidget(
                  message:
                      'Could not load sector detail.\nMake sure your backend is running.',
                  onRetry: _fetch,
                )
              : _buildContent(),
    );
  }

  // ── Skeleton loading ─────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(height: 80, radius: 12),
          const SizedBox(height: 24),
          const ShimmerBox(height: 16, radius: 6),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
          ]),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
          ]),
          const SizedBox(height: 24),
          const ShimmerBox(height: 16, radius: 6),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 100, radius: 12)),
          ]),
        ],
      ),
    );
  }

  // ── Main content ─────────────────────────────────────────────────
  Widget _buildContent() {
    final d = _data!;
    final price     = (d['price']     as num).toDouble();
    final change1d  = (d['change_1d'] as num).toDouble();
    final ytdPct    = (d['ytd_pct']   as num).toDouble();
    final w52High   = (d['week52_high'] as num).toDouble();
    final w52Pct    = (d['week52_high_pct'] as num).toDouble();
    final ma10      = (d['ma10']      as num).toDouble();
    final ma10Pct   = (d['ma10_pct']  as num).toDouble();
    final ma20      = (d['ma20']      as num).toDouble();
    final ma20Pct   = (d['ma20_pct']  as num).toDouble();
    final ma50      = (d['ma50']      as num).toDouble();
    final ma50Pct   = (d['ma50_pct']  as num).toDouble();
    final ma200     = (d['ma200']     as num).toDouble();
    final ma200Pct  = (d['ma200_pct'] as num).toDouble();
    final rsi14     = (d['rsi14']     as num).toDouble();
    final closes50d = (d['closes_50d'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        <double>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Price header card ─────────────────────────────────
          _PriceHeaderCard(price: price, change1d: change1d),
          const SizedBox(height: 12),

          // ── Sparkline chart ───────────────────────────────────
          if (closes50d.length >= 2)
            _SparklineChart(closes: closes50d, change1d: change1d),
          const SizedBox(height: 24),

          // ── Moving Averages section ───────────────────────────
          _sectionLabel('Moving Averages'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _MaCard(label: 'MA 10',  value: ma10,  pct: ma10Pct)),
            const SizedBox(width: 12),
            Expanded(child: _MaCard(label: 'MA 20',  value: ma20,  pct: ma20Pct)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MaCard(label: 'MA 50',  value: ma50,  pct: ma50Pct)),
            const SizedBox(width: 12),
            Expanded(child: _MaCard(label: 'MA 200', value: ma200, pct: ma200Pct)),
          ]),
          const SizedBox(height: 24),

          // ── Momentum section ──────────────────────────────────
          _sectionLabel('Momentum'),
          const SizedBox(height: 10),
          _RsiCard(rsi: rsi14),
          const SizedBox(height: 24),

          // ── Performance section ───────────────────────────────
          _sectionLabel('Performance'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _PerformanceCard(label: 'YTD', pct: ytdPct)),
            const SizedBox(width: 12),
            Expanded(child: _Week52Card(high: w52High, pct: w52Pct)),
          ]),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppColors.dim,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ── Sparkline chart (50-day closes) ───────────────────────────────
class _SparklineChart extends StatelessWidget {
  final List<double> closes;
  final double change1d;

  const _SparklineChart({required this.closes, required this.change1d});

  @override
  Widget build(BuildContext context) {
    final isPos  = change1d >= 0;
    final color  = isPos ? AppColors.green : AppColors.red;
    final minY   = closes.reduce((a, b) => a < b ? a : b);
    final maxY   = closes.reduce((a, b) => a > b ? a : b);
    final padY   = (maxY - minY) * 0.1 + 0.01;

    final spots  = closes
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        child: LineChart(
          LineChartData(
            minY: minY - padY,
            maxY: maxY + padY,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.25,
                color: color,
                barWidth: 1.8,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.18),
                      color.withValues(alpha: 0.0),
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
    );
  }
}

// ── Price header card ──────────────────────────────────────────────
class _PriceHeaderCard extends StatelessWidget {
  final double price;
  final double change1d;

  const _PriceHeaderCard({required this.price, required this.change1d});

  @override
  Widget build(BuildContext context) {
    final isPos     = change1d >= 0;
    final color     = isPos ? AppColors.green : AppColors.red;
    final sign      = isPos ? '+' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '\$${price.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$sign${change1d.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── MA card ───────────────────────────────────────────────────────
class _MaCard extends StatelessWidget {
  final String label;
  final double value;
  final double pct;

  const _MaCard({
    required this.label,
    required this.value,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final isAbove = pct >= 0;
    final color   = isAbove ? AppColors.green : AppColors.red;
    final sign    = isAbove ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.dim,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\$${value.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$sign${pct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── YTD performance card ──────────────────────────────────────────
class _PerformanceCard extends StatelessWidget {
  final String label;
  final double pct;

  const _PerformanceCard({required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    final isPos = pct >= 0;
    final color = isPos ? AppColors.green : AppColors.red;
    final sign  = isPos ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.dim,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$sign${pct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 52-week high card ─────────────────────────────────────────────
class _Week52Card extends StatelessWidget {
  final double high;
  final double pct;

  const _Week52Card({required this.high, required this.pct});

  @override
  Widget build(BuildContext context) {
    final isPos = pct >= 0;
    final color = isPos ? AppColors.green : AppColors.red;
    final sign  = isPos ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '52W HIGH',
            style: TextStyle(
              color: AppColors.dim,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\$${high.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$sign${pct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── RSI card ──────────────────────────────────────────────────────
class _RsiCard extends StatelessWidget {
  final double rsi;
  const _RsiCard({required this.rsi});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (rsi >= 70) {
      color = AppColors.red;
      label = 'Overbought';
    } else if (rsi <= 30) {
      color = AppColors.green;
      label = 'Oversold';
    } else {
      color = AppColors.text;
      label = 'Neutral';
    }

    final double fraction = (rsi / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RSI 14',
                  style: TextStyle(
                      color: AppColors.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── RSI value ──────────────────────────────────────────
          Text(rsi.toStringAsFixed(1),
              style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // ── Progress bar with zones ─────────────────────────────
          Stack(
            children: [
              // Track
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Oversold zone 0–30
              FractionallySizedBox(
                widthFactor: 0.30,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(3)),
                  ),
                ),
              ),
              // Overbought zone 70–100
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.30,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
              // Current RSI marker
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Zone labels ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0',   style: TextStyle(color: AppColors.dim,   fontSize: 10)),
              Text('30',  style: const TextStyle(color: AppColors.green, fontSize: 10)),
              Text('70',  style: const TextStyle(color: AppColors.red,   fontSize: 10)),
              Text('100', style: TextStyle(color: AppColors.dim,   fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
