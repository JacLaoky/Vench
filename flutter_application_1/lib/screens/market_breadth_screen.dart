import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

class MarketBreadthScreen extends StatefulWidget {
  const MarketBreadthScreen({super.key});

  @override
  State<MarketBreadthScreen> createState() => _MarketBreadthScreenState();
}

class _MarketBreadthScreenState extends State<MarketBreadthScreen> {
  String _period = '1D';
  static const _periods = ['1D', '1W', '1M'];

  bool _loading = true;
  bool _error = false;

  List<dynamic> _indices = [];
  double _vix = 0.0;
  double _vixChange = 0.0;
  int _sectorsPositive = 0;
  int _sectorsTotal = 0;

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
        Uri.parse('$kBaseUrl/api/market_breadth?period=$_period'),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['status'] == 'success') {
          setState(() {
            _indices         = body['indices'] as List;
            _vix             = (body['vix'] as num).toDouble();
            _vixChange       = (body['vix_change'] as num).toDouble();
            _sectorsPositive = (body['sectors_positive'] as num).toInt();
            _sectorsTotal    = (body['sectors_total'] as num).toInt();
            _loading         = false;
          });
          return;
        }
      }
      setState(() { _loading = false; _error = true; });
    } catch (_) {
      setState(() { _loading = false; _error = true; });
    }
  }

  void _onPeriodChanged(String p) {
    if (p == _period) return;
    setState(() => _period = p);
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
        title: const Text('Market Breadth',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildPeriodToggle(),
          const SizedBox(height: 12),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildPeriodToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: _periods.map((p) {
            final sel = p == _period;
            return Expanded(
              child: GestureDetector(
                onTap: () => _onPeriodChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.darkBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p,
                    style: TextStyle(
                      color: sel ? AppColors.text : AppColors.dim,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error) {
      return ErrorRetryWidget(
        message: 'Could not load market breadth.\nMake sure your backend is running.',
        onRetry: _fetch,
      );
    }
    return RefreshIndicator(
      color: AppColors.blue,
      backgroundColor: AppColors.card,
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _sectionLabel('Major Indices'),
            const SizedBox(height: 10),
            _buildIndicesGrid(),
            const SizedBox(height: 20),
            _sectionLabel('Volatility (VIX)'),
            const SizedBox(height: 10),
            _buildVixCard(),
            const SizedBox(height: 20),
            _sectionLabel('Sector Breadth'),
            const SizedBox(height: 10),
            _buildBreadthCard(),
            const SizedBox(height: 20),
          ],
        ),
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
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildIndicesGrid() {
    // 2-column grid
    final rows = <Widget>[];
    for (int i = 0; i < _indices.length; i += 2) {
      final left  = _indices[i];
      final right = i + 1 < _indices.length ? _indices[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: _IndexCard(data: left)),
            const SizedBox(width: 12),
            right != null
                ? Expanded(child: _IndexCard(data: right))
                : const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < _indices.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  Widget _buildVixCard() {
    Color vixColor;
    String vixLabel;
    if (_vix < 15) {
      vixColor = AppColors.green;
      vixLabel = 'Low Volatility';
    } else if (_vix < 25) {
      vixColor = const Color(0xFFFF9800);
      vixLabel = 'Moderate';
    } else if (_vix < 35) {
      vixColor = AppColors.red;
      vixLabel = 'Elevated Fear';
    } else {
      vixColor = const Color(0xFFB71C1C);
      vixLabel = 'Extreme Fear';
    }

    final changeSign  = _vixChange >= 0 ? '+' : '';
    final changeColor = _vixChange >= 0 ? AppColors.red : AppColors.green;
    // VIX going up = bad (more fear), so color is inverted

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VIX',
            style: TextStyle(color: AppColors.dim, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _vix.toStringAsFixed(1),
                style: TextStyle(
                  color: vixColor,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: vixColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        vixLabel,
                        style: TextStyle(
                          color: vixColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$changeSign${_vixChange.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: changeColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreadthCard() {
    final ratio    = _sectorsTotal > 0 ? _sectorsPositive / _sectorsTotal : 0.0;
    Color barColor;
    if (_sectorsPositive > 6) {
      barColor = AppColors.green;
    } else if (_sectorsPositive < 5) {
      barColor = AppColors.red;
    } else {
      barColor = const Color(0xFFFF9800);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sectors Positive Today',
            style: TextStyle(color: AppColors.dim, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            '$_sectorsPositive / $_sectorsTotal',
            style: TextStyle(
              color: barColor,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}% of sectors advancing',
            style: TextStyle(color: AppColors.dim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(height: 13, width: 110, radius: 4),
          const SizedBox(height: 10),
          Row(children: const [
            Expanded(child: ShimmerBox(height: 90)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 90)),
          ]),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(child: ShimmerBox(height: 90)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 90)),
          ]),
          const SizedBox(height: 20),
          const ShimmerBox(height: 13, width: 130, radius: 4),
          const SizedBox(height: 10),
          const ShimmerBox(height: 110),
          const SizedBox(height: 20),
          const ShimmerBox(height: 13, width: 120, radius: 4),
          const SizedBox(height: 10),
          const ShimmerBox(height: 110),
        ],
      ),
    );
  }
}

// ── Individual Index Card ──────────────────────────────────────────────────────

class _IndexCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _IndexCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final double changePct = (data['change_pct'] as num).toDouble();
    final double price     = (data['price'] as num).toDouble();
    final bool   positive  = changePct >= 0;
    final Color  color     = positive ? AppColors.green : AppColors.red;
    final String sign      = positive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['name'] as String,
            style: TextStyle(
              color: AppColors.dim,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data['ticker'] as String,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${price.toStringAsFixed(2)}',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$sign${changePct.toStringAsFixed(2)}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
