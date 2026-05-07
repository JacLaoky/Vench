import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';
import 'package:flutter_application_1/screens/sector_detail_screen.dart';

// ================= 🏭 Sector & Theme Performance Screen =================
class SectorsScreen extends StatefulWidget {
  const SectorsScreen({super.key});

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends State<SectorsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String _period = '1D';
  static const _periods = ['1D', '1W', '1M'];

  // Per-tab state keyed by type string
  final _data    = <String, List<dynamic>>{'sector': [], 'theme': []};
  final _loading = <String, bool>{'sector': true,  'theme': false};
  final _error   = <String, bool>{'sector': false, 'theme': false};
  final _fetched = <String, bool>{'sector': false, 'theme': false};

  String get _activeType => _tabController.index == 0 ? 'sector' : 'theme';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          // Lazy-fetch: only fetch theme tab the first time it's opened
          if (!_fetched[_activeType]!) _fetch(_activeType);
          setState(() {}); // rebuild summary bar
        }
      });
    _fetch('sector');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetch(String type) async {
    setState(() {
      _loading[type] = true;
      _error[type]   = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/api/sectors?period=$_period&type=$type'),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['status'] == 'success') {
          setState(() {
            _data[type]    = body['data'] as List;
            _loading[type] = false;
            _fetched[type] = true;
          });
          return;
        }
      }
      setState(() { _loading[type] = false; _error[type] = true; });
    } catch (_) {
      setState(() { _loading[type] = false; _error[type] = true; });
    }
  }

  // Refetch both tabs when period changes
  void _onPeriodChanged(String p) {
    setState(() {
      _period = p;
      // Invalidate fetched flag so both tabs reload
      _fetched['sector'] = false;
      _fetched['theme']  = false;
    });
    _fetch('sector');
    if (_tabController.index == 1) _fetch('theme');
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
        title: const Text('Market Heatmap',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.blue,
            indicatorWeight: 2.5,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.dim,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            tabs: const [
              Tab(text: 'Sectors'),
              Tab(text: 'Themes'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildPeriodToggle(),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent('sector'),
                _buildTabContent('theme'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Period toggle ───────────────────────────────────────────────
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
                onTap: () { if (!sel) _onPeriodChanged(p); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.darkBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(p,
                      style: TextStyle(
                        color: sel ? AppColors.text : AppColors.dim,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Tab content ─────────────────────────────────────────────────
  Widget _buildTabContent(String type) {
    if (_loading[type]!) return _buildSkeleton();
    if (_error[type]!) {
      return ErrorRetryWidget(
        message: 'Could not load data.\nMake sure your backend is running.',
        onRetry: () => _fetch(type),
      );
    }
    final list = _data[type]!;
    return RefreshIndicator(
      color: AppColors.blue,
      backgroundColor: AppColors.card,
      onRefresh: () => _fetch(type),
      child: list.isEmpty
          ? Center(
              child: Text('No data available.',
                  style: TextStyle(color: AppColors.dim)))
          : Column(
              children: [
                _buildSummary(list),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final s = list[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SectorDetailScreen(
                              ticker: s['ticker'] as String,
                              name: s['name'] as String,
                              changePct: (s['change_pct'] as num).toDouble(),
                              price: (s['price'] as num).toDouble(),
                            ),
                          ),
                        ),
                        child: _SectorCard(sector: s),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // ── Best / Worst / Avg summary bar ──────────────────────────────
  Widget _buildSummary(List<dynamic> list) {
    final sorted = List.from(list)
      ..sort((a, b) =>
          (b['change_pct'] as num).compareTo(a['change_pct'] as num));
    final best  = sorted.first;
    final worst = sorted.last;
    final avg   = list.fold<double>(
            0, (s, e) => s + (e['change_pct'] as num).toDouble()) /
        list.length;
    final avgColor = avg >= 0 ? AppColors.green : AppColors.red;
    final avgSign  = avg >= 0 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        _chip('Best',
            '${best['ticker']}  ${_pctStr(best['change_pct'])}',
            AppColors.green),
        const SizedBox(width: 8),
        _chip('Worst',
            '${worst['ticker']}  ${_pctStr(worst['change_pct'])}',
            AppColors.red),
        const SizedBox(width: 8),
        _chip('Avg', '$avgSign${avg.toStringAsFixed(2)}%', avgColor),
      ]),
    );
  }

  Widget _chip(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.dim, fontSize: 10)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  // ── Shimmer skeleton ────────────────────────────────────────────
  Widget _buildSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: 10,
      itemBuilder: (_, __) => const ShimmerBox(height: 110, radius: 14),
    );
  }
}

// ── Sector / Theme card ──────────────────────────────────────────
class _SectorCard extends StatelessWidget {
  final dynamic sector;
  const _SectorCard({required this.sector});

  @override
  Widget build(BuildContext context) {
    final name   = sector['name']       as String;
    final ticker = sector['ticker']     as String;
    final pct    = (sector['change_pct'] as num).toDouble();
    final price  = (sector['price']     as num).toDouble();
    final isPos  = pct >= 0;
    final color  = isPos ? AppColors.green : AppColors.red;

    final intensity = (pct.abs() / 5).clamp(0.0, 1.0);
    final bgAlpha   = 0.04 + intensity * 0.18;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: color.withValues(alpha: bgAlpha * 1.8), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(ticker,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              if (price > 0)
                Text('\$${price.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: AppColors.dim, fontSize: 11)),
            ],
          ),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.dim, fontSize: 11)),
          Text(_pctStr(pct),
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

String _pctStr(num pct) {
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}
